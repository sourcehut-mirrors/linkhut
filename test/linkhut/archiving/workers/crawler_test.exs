defmodule Linkhut.Archiving.Workers.CrawlerTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Snapshot
  alias Linkhut.Archiving.Workers.{Archiver, Crawler}

  @data_dir Linkhut.Config.archiving(:data_dir)

  setup do
    File.rm_rf!(@data_dir)
    File.mkdir_p!(@data_dir)
    on_exit(fn -> File.rm_rf(@data_dir) end)
    :ok
  end

  defp create_pending_snapshot(user, link, type \\ "singlefile") do
    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, nil, %{
        type: type,
        state: :pending
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

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, nil, %{
          type: "singlefile",
          state: :complete,
          storage_key: "local:/tmp/test"
        })

      job = make_job(snapshot, user, link)

      assert :ok = Crawler.perform(job)
      assert Repo.get(Snapshot, snapshot.id).state == :complete
    end

    test "returns :ok for pending_deletion snapshot" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, nil, %{
          type: "singlefile",
          state: :pending_deletion
        })

      job = make_job(snapshot, user, link)

      assert :ok = Crawler.perform(job)
      assert Repo.get(Snapshot, snapshot.id).state == :pending_deletion
    end
  end

  describe "perform/1 — unsupported crawler" do
    test "marks snapshot as failed for unsupported crawler type" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link, "nonexistent")
      job = make_job(snapshot, user, link, type: "nonexistent")

      assert {:error, :unsupported_crawler} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :failed
      assert updated.archive_metadata["error"] =~ "unsupported_crawler"
    end
  end

  describe "perform/1 — crawler fetch error" do
    test "marks snapshot as failed when crawler returns error" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      snapshot = create_pending_snapshot(user, link)

      # Use a mock crawler that fails
      set_crawlers([Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler])

      job = make_job(snapshot, user, link, type: "failing")

      assert {:error, %{msg: "simulated failure"}} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :failed
      assert updated.archive_metadata["error"] =~ "simulated failure"
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

    test "marks old archives for deletion on recrawl" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      # Create an old archive
      {:ok, old_job} = insert_oban_job(user.id, link.id, link.url)
      {:ok, old_archive} = Archiving.get_or_create_archive(old_job.id, link.id, user.id, link.url)

      # Create a new archive for the recrawl (recrawl: true to avoid uniqueness de-dupe)
      {:ok, new_job} = insert_oban_job(user.id, link.id, link.url, recrawl: true)
      {:ok, new_archive} = Archiving.get_or_create_archive(new_job.id, link.id, user.id, link.url)

      snapshot = create_pending_snapshot(user, link)
      Archiving.update_snapshot(snapshot, %{archive_id: new_archive.id})

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
      # New archive should remain active
      assert Repo.get(Linkhut.Archiving.Archive, new_archive.id).state == :active
    end
  end

  # --- Helpers ---

  defp set_crawlers(crawlers) do
    config = Application.get_env(:linkhut, Linkhut)
    archiving = Keyword.put(config[:archiving], :crawlers, crawlers)
    Application.put_env(:linkhut, Linkhut, Keyword.put(config, :archiving, archiving))

    on_exit(fn ->
      Application.put_env(:linkhut, Linkhut, config)
    end)
  end

  defp insert_oban_job(user_id, link_id, url, opts \\ []) do
    args =
      %{"user_id" => user_id, "link_id" => link_id, "url" => url}
      |> then(fn args ->
        if Keyword.get(opts, :recrawl, false),
          do: Map.put(args, "recrawl", true),
          else: args
      end)

    Archiver.new(args)
    |> Oban.insert()
  end
end

# Test crawler modules defined outside the test module for use in tests

defmodule Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler do
  @behaviour Linkhut.Archiving.Crawler

  @impl true
  def type, do: "failing"

  @impl true
  def can_handle?(_url, _meta), do: true

  @impl true
  def fetch(_context), do: {:error, %{msg: "simulated failure"}}
end

defmodule Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler do
  @behaviour Linkhut.Archiving.Crawler

  @impl true
  def type, do: "success"

  @impl true
  def can_handle?(_url, _meta), do: true

  @impl true
  def fetch(_context) do
    staging_dir =
      Path.join(System.tmp_dir!(), "linkhut_test_crawl_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(staging_dir)
    path = Path.join(staging_dir, "result")
    File.write!(path, "<html>test content</html>")

    {:ok, %{path: path, version: "1.0.0", response_code: 200}}
  end
end
