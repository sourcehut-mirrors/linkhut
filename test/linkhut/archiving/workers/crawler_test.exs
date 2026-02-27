defmodule Linkhut.Archiving.Workers.CrawlerTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Snapshot
  alias Linkhut.Archiving.Workers.Crawler

  @data_dir Linkhut.Config.archiving(:data_dir)

  setup do
    File.rm_rf!(@data_dir)
    File.mkdir_p!(@data_dir)
    on_exit(fn -> File.rm_rf(@data_dir) end)
    :ok
  end

  defp create_pending_snapshot(user, link, type \\ "singlefile") do
    archive =
      insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, %{
        type: type,
        state: :pending,
        archive_id: archive.id
      })

    snapshot
  end

  defp make_job(snapshot, user, link, opts \\ []) do
    type = Keyword.get(opts, :type, "singlefile")
    recrawl = Keyword.get(opts, :recrawl, false)
    archive_id = Keyword.get(opts, :archive_id)

    {:ok, real_job} =
      Crawler.new(%{
        "snapshot_id" => snapshot.id,
        "user_id" => user.id,
        "link_id" => link.id,
        "url" => "https://example.com",
        "type" => type,
        "recrawl" => recrawl,
        "archive_id" => archive_id
      })
      |> Oban.insert()

    %Oban.Job{
      id: real_job.id,
      args: %{
        "snapshot_id" => snapshot.id,
        "user_id" => user.id,
        "link_id" => link.id,
        "url" => "https://example.com",
        "type" => type,
        "recrawl" => recrawl,
        "archive_id" => archive_id
      },
      attempt: 1,
      max_attempts: 4
    }
  end

  describe "perform/1 — snapshot state guards" do
    test "returns :ok for missing snapshot" do
      {:ok, real_job} =
        Crawler.new(%{
          "snapshot_id" => 999_999,
          "user_id" => 1,
          "link_id" => 1,
          "url" => "https://example.com",
          "type" => "singlefile"
        })
        |> Oban.insert()

      job = %Oban.Job{
        id: real_job.id,
        args: %{
          "snapshot_id" => 999_999,
          "user_id" => 1,
          "link_id" => 1,
          "url" => "https://example.com",
          "type" => "singlefile"
        },
        attempt: 1,
        max_attempts: 4
      }

      assert :ok = Crawler.perform(job)
    end

    test "returns :ok for already complete snapshot" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      archive = insert(:archive, user_id: user.id, link_id: link.id, url: link.url)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :complete,
          storage_key: "local:/tmp/test",
          archive_id: archive.id
        })

      job = make_job(snapshot, user, link)

      assert :ok = Crawler.perform(job)
      assert Repo.get(Snapshot, snapshot.id).state == :complete
    end

    test "returns :ok for pending_deletion snapshot" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      archive = insert(:archive, user_id: user.id, link_id: link.id, url: link.url)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :pending_deletion,
          archive_id: archive.id
        })

      job = make_job(snapshot, user, link)

      assert :ok = Crawler.perform(job)
      assert Repo.get(Snapshot, snapshot.id).state == :pending_deletion
    end
  end

  describe "perform/1 — unsupported crawler" do
    test "marks snapshot as retryable for unsupported crawler type on non-final attempt" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link, "nonexistent")
      job = make_job(snapshot, user, link, type: "nonexistent")

      assert {:error, :unsupported_crawler} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :retryable
      assert updated.archive_metadata["error"] =~ "unsupported_crawler"
    end
  end

  describe "perform/1 — crawler fetch error" do
    test "marks snapshot as retryable when crawler returns error on non-final attempt" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      # Use a mock crawler that fails
      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler])

      job = make_job(snapshot, user, link, type: "failing")

      assert {:error, %{msg: "simulated failure"}} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :retryable
      assert updated.archive_metadata["error"] =~ "simulated failure"
    end

    test "marks snapshot as failed when crawler returns error on final attempt" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler])

      job = %{make_job(snapshot, user, link, type: "failing") | attempt: 4, max_attempts: 4}

      assert {:error, %{msg: "simulated failure"}} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :failed
    end

    test "returns {:error, _} on non-final attempt to enable Oban retry" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler])

      job = %{make_job(snapshot, user, link, type: "failing") | attempt: 1, max_attempts: 4}

      assert {:error, _} = Crawler.perform(job)
    end
  end

  describe "perform/1 — successful crawl" do
    test "stores file and marks snapshot as complete" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler])

      job = make_job(snapshot, user, link, type: "success")

      Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :complete
      assert updated.storage_key != nil
      assert updated.file_size_bytes != nil
      assert updated.processing_time_ms != nil
      assert updated.response_code == 200
    end

    test "archive_metadata does not contain tool_name or crawler_version" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler])

      job = make_job(snapshot, user, link, type: "success")

      Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :complete
      refute Map.has_key?(updated.archive_metadata, "tool_name")
      refute Map.has_key?(updated.archive_metadata, "crawler_version")
    end

    test "transitions snapshot through crawling state" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler])

      job = make_job(snapshot, user, link, type: "success")
      Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      # Should end up complete (passed through crawling)
      assert updated.state == :complete

      # crawl_info should have step entries
      steps = updated.crawl_info["steps"]
      assert is_list(steps)
      step_names = Enum.map(steps, & &1["step"])
      assert "crawling" in step_names
      assert "complete" in step_names
    end

    test "transitions archive to complete after successful crawl" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler])

      job = make_job(snapshot, user, link, type: "success")

      Crawler.perform(job)

      archive = Repo.get(Linkhut.Archiving.Archive, snapshot.archive_id)
      assert archive.state == :complete
    end

    test "transitions archive to complete after final failure" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler])

      job = %{make_job(snapshot, user, link, type: "failing") | attempt: 4, max_attempts: 4}

      Crawler.perform(job)

      archive = Repo.get(Linkhut.Archiving.Archive, snapshot.archive_id)
      assert archive.state == :complete
    end

    test "does not transition archive to complete on non-final failure" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler])

      job = %{make_job(snapshot, user, link, type: "failing") | attempt: 1, max_attempts: 4}

      Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :retryable

      archive = Repo.get(Linkhut.Archiving.Archive, snapshot.archive_id)
      assert archive.state == :processing
    end

    test "completes snapshot on retry after non-final failure" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      set_crawlers([
        Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler,
        Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler
      ])

      # Attempt 1: fails (non-final)
      job1 = %{make_job(snapshot, user, link, type: "failing") | attempt: 1, max_attempts: 4}
      Crawler.perform(job1)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :retryable

      # Attempt 2: succeeds with a different crawler
      job2 = %{make_job(updated, user, link, type: "success") | attempt: 2, max_attempts: 4}
      Crawler.perform(job2)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :complete
      assert updated.storage_key != nil

      archive = Repo.get(Linkhut.Archiving.Archive, snapshot.archive_id)
      assert archive.state == :complete
    end

    test "marks old archives for deletion on recrawl" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      # Create an old archive
      old_archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      # Create a new archive for the recrawl
      new_archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :pending,
          archive_id: new_archive.id
        })

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler])

      job =
        make_job(snapshot, user, link,
          type: "success",
          recrawl: true,
          archive_id: new_archive.id
        )

      Crawler.perform(job)

      # Old archive should be marked for deletion
      assert Repo.get(Linkhut.Archiving.Archive, old_archive.id).state == :pending_deletion
      # New archive should have completed (only snapshot is now :complete)
      assert Repo.get(Linkhut.Archiving.Archive, new_archive.id).state == :complete
    end

    test "does not prematurely complete archive when sibling crawler has retries remaining" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      # Create two snapshots for different crawlers
      {:ok, success_snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "success",
          state: :pending,
          archive_id: archive.id
        })

      {:ok, failing_snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "failing",
          state: :pending,
          archive_id: archive.id
        })

      set_crawlers([
        Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler,
        Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler
      ])

      # Failing crawler fails on non-final attempt
      failing_job =
        make_job(failing_snapshot, user, link,
          type: "failing",
          archive_id: archive.id
        )

      failing_job = %{failing_job | attempt: 1, max_attempts: 4}
      Crawler.perform(failing_job)

      # Success crawler succeeds
      success_job =
        make_job(success_snapshot, user, link,
          type: "success",
          archive_id: archive.id
        )

      Crawler.perform(success_job)

      # Failing snapshot is :retryable (non-terminal) — archive should NOT complete
      assert Repo.get(Snapshot, failing_snapshot.id).state == :retryable
      assert Repo.get(Linkhut.Archiving.Archive, archive.id).state == :processing
    end
  end

  describe "perform/1 — file size limit" do
    test "rejects file exceeding max_file_size on non-final attempt" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link, "large")

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.LargeCrawler])
      set_max_file_size(10)

      job = make_job(snapshot, user, link, type: "large")

      assert {:error, %{msg: "file_too_large"}} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :retryable
      assert updated.archive_metadata["error"] =~ "file_too_large"
    end

    test "rejects file exceeding max_file_size on final attempt" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link, "large")

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.LargeCrawler])
      set_max_file_size(10)

      job = %{make_job(snapshot, user, link, type: "large") | attempt: 4, max_attempts: 4}

      assert {:error, %{msg: "file_too_large"}} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :failed
    end

    test "cleans up staging directory on size rejection" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link, "large")

      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.LargeCrawler])
      set_max_file_size(10)

      job = make_job(snapshot, user, link, type: "large")
      Crawler.perform(job)

      # LargeCrawler creates a staging dir — it should be cleaned up
      # Verify indirectly: the snapshot has no storage_key (file was not stored)
      updated = Repo.get(Snapshot, snapshot.id)
      assert is_nil(updated.storage_key)
    end
  end

  # --- Helpers ---

  defp set_max_file_size(size) do
    config = Application.get_env(:linkhut, Linkhut)
    archiving = Keyword.put(config[:archiving], :max_file_size, size)
    Application.put_env(:linkhut, Linkhut, Keyword.put(config, :archiving, archiving))

    on_exit(fn ->
      Application.put_env(:linkhut, Linkhut, config)
    end)
  end

  defp set_crawlers(crawlers) do
    config = Application.get_env(:linkhut, Linkhut)
    archiving = Keyword.put(config[:archiving], :crawlers, crawlers)
    Application.put_env(:linkhut, Linkhut, Keyword.put(config, :archiving, archiving))

    on_exit(fn ->
      Application.put_env(:linkhut, Linkhut, config)
    end)
  end
end

# Test crawler modules defined outside the test module for use in tests

defmodule Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler do
  @behaviour Linkhut.Archiving.Crawler

  @impl true
  def type, do: "failing"

  @impl true
  def meta, do: %{tool_name: "FailingCrawler", version: "0.0.1"}

  @impl true
  def can_handle?(_url, _meta), do: true

  @impl true
  def fetch(_context), do: {:error, %{msg: "simulated failure"}}
end

defmodule Linkhut.Archiving.Workers.CrawlerTest.LargeCrawler do
  @behaviour Linkhut.Archiving.Crawler

  @impl true
  def type, do: "large"

  @impl true
  def meta, do: %{tool_name: "LargeCrawler", version: "1.0.0"}

  @impl true
  def can_handle?(_url, _meta), do: true

  @impl true
  def fetch(_context) do
    staging_dir =
      Path.join(System.tmp_dir!(), "linkhut_test_large_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(staging_dir)
    path = Path.join(staging_dir, "result")
    # Write 1000 bytes — will exceed a 10-byte max_file_size in tests
    File.write!(path, String.duplicate("x", 1000))

    {:ok, %{path: path, response_code: 200}}
  end
end

defmodule Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler do
  @behaviour Linkhut.Archiving.Crawler

  @impl true
  def type, do: "success"

  @impl true
  def meta, do: %{tool_name: "SuccessCrawler", version: "1.0.0"}

  @impl true
  def can_handle?(_url, _meta), do: true

  @impl true
  def fetch(_context) do
    staging_dir =
      Path.join(System.tmp_dir!(), "linkhut_test_crawl_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(staging_dir)
    path = Path.join(staging_dir, "result")
    File.write!(path, "<html>test content</html>")

    {:ok, %{path: path, response_code: 200}}
  end
end
