defmodule Linkhut.Archiving.Workers.CrawlerTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving.{CrawlRun, Snapshot}
  alias Linkhut.Archiving.Workers.Crawler

  @data_dir Linkhut.Config.archiving(:data_dir)

  setup do
    File.rm_rf!(@data_dir)
    File.mkdir_p!(@data_dir)
    on_exit(fn -> File.rm_rf(@data_dir) end)
    :ok
  end

  defp create_pending_snapshot(source) do
    link = insert(:link, user_id: insert(:user).id)
    insert(:crawl_run, link_id: link.id)

    {:ok, snapshot} =
      create_snapshot(link.id, link.user_id, %{
        format: if(source in ["wayback", "external"], do: "reference", else: "webpage"),
        source: source,
        state: :pending
      })

    snapshot
  end

  defp run_for(snapshot) do
    Repo.one(
      from r in CrawlRun,
        where: r.link_id == ^snapshot.link_id,
        order_by: [desc: r.id],
        limit: 1
    )
  end

  defp make_job(snapshot) do
    args = %{
      "snapshot_id" => snapshot.id,
      "crawl_run_id" => run_for(snapshot).id,
      "url" => "https://example.com/page"
    }

    %Oban.Job{args: args, attempt: 1, max_attempts: 4}
  end

  defp events(run), do: Repo.preload(run, :events, force: true).events

  describe "perform/1 — snapshot state guards" do
    test "returns :ok for missing snapshot" do
      job = %Oban.Job{args: %{"snapshot_id" => 999_999, "crawl_run_id" => 1}}

      assert :ok = Crawler.perform(job)
    end

    test "a redelivered job for a finished snapshot does nothing" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      for state <- [:complete, :not_available, :failed] do
        crawl_run =
          insert(:crawl_run, link_id: link.id)

        snapshot =
          insert(:snapshot,
            user_id: user.id,
            link_id: link.id,
            state: state
          )

        assert :ok = Crawler.perform(make_job(snapshot)), "for #{state}"
        assert Repo.get(Snapshot, snapshot.id).state == state
        assert events(crawl_run) == []
      end
    end
  end

  describe "perform/1 — unsupported crawler" do
    test "fails the snapshot and cancels the job without retrying" do
      snapshot = create_pending_snapshot("nonexistent")
      job = make_job(snapshot)

      assert {:cancel, "unsupported_crawler"} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :failed
      assert updated.archive_metadata["error_code"] == "unsupported_crawler"
    end
  end

  describe "perform/1 — crawler fetch error" do
    test "leaves the snapshot crawling and logs the attempt when retries remain" do
      snapshot = create_pending_snapshot("failing")

      # Use a mock crawler that fails
      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler
      ])

      job = make_job(snapshot)

      assert {:error, %{msg: "simulated failure"}} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :crawling
      assert updated.failed_at == nil
      assert updated.retry_count == 0

      assert %{
               event: "crawler.attempt_failed",
               level: :warning,
               snapshot_id: snapshot_id,
               data: %{"error" => "simulated failure", "attempt" => 1, "max_attempts" => 4}
             } = List.last(events(run_for(snapshot)))

      assert snapshot_id == snapshot.id
    end

    test "marks snapshot as failed when crawler returns error on final attempt" do
      snapshot = create_pending_snapshot("failing")

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler
      ])

      job = %{make_job(snapshot) | attempt: 4, max_attempts: 4}

      assert {:error, %{msg: "simulated failure"}} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :failed
      assert updated.retry_count == 3
      assert updated.archive_metadata["error"] == "simulated failure"

      assert %{event: "crawler.failed", level: :error, data: %{"attempt" => 4}} =
               events(run_for(snapshot))
               |> Enum.find(&(&1.event == "crawler.failed"))
    end
  end

  describe "perform/1 — crawler exception" do
    test "treats a crash in the crawler as a failed attempt" do
      snapshot = create_pending_snapshot("raising")

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Workers.CrawlerTest.RaisingCrawler
      ])

      job = make_job(snapshot)

      assert {:error, "kaboom!"} = Crawler.perform(job)

      assert Repo.get(Snapshot, snapshot.id).state == :crawling

      assert %{event: "crawler.attempt_failed", data: %{"error" => "kaboom!"}} =
               List.last(events(run_for(snapshot)))
    end
  end

  describe "perform/1 — rate limiting" do
    test "snoozes job when crawler is rate limited" do
      snapshot = create_pending_snapshot("ratelimited")

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Workers.CrawlerTest.RateLimitedCrawler
      ])

      # Exhaust the rate limit bucket (limit: 1)
      assert {:allow, _} = Linkhut.Archiving.RateLimit.hit("crawler:ratelimited", 60_000, 1)

      job = make_job(snapshot)

      assert {:snooze, seconds} = Crawler.perform(job)
      assert seconds >= 60

      # Snapshot should still be pending (not crawling)
      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :pending

      assert %{data: %{"snooze_seconds" => ^seconds}} =
               snapshot
               |> run_for()
               |> events()
               |> Enum.find(&(&1.event == "crawler.rate_limited"))
    end
  end

  describe "perform/1 — not available" do
    test "marks snapshot as :not_available and returns :ok" do
      snapshot = create_pending_snapshot("notavail")

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Workers.CrawlerTest.NotAvailableCrawler
      ])

      job = make_job(snapshot)

      assert :ok = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :not_available
      assert is_nil(updated.storage_key)
      assert updated.processing_time_ms != nil
    end
  end

  describe "perform/1 — successful crawl" do
    test "stores file and marks snapshot as complete" do
      snapshot = create_pending_snapshot("success")

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler
      ])

      job = make_job(snapshot)

      Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :complete
      assert updated.storage_key != nil
      assert updated.file_size_bytes != nil
      assert updated.processing_time_ms != nil
      assert updated.response_code == 200
    end
  end

  describe "perform/1 — external result" do
    test "stores external result and marks snapshot as complete" do
      snapshot = create_pending_snapshot("external")

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Workers.CrawlerTest.ExternalCrawler
      ])

      job = make_job(snapshot)

      Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :complete

      assert updated.storage_key ==
               "external:https://web.archive.org/web/20250301/https://example.com"

      assert is_nil(updated.file_size_bytes)
      assert updated.processing_time_ms != nil
      assert updated.response_code == 200
    end
  end

  describe "perform/1 — file size limit" do
    test "rejects file exceeding max_file_size without retrying" do
      snapshot = create_pending_snapshot("large")

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Workers.CrawlerTest.LargeCrawler
      ])

      put_override(Linkhut.Archiving, :max_file_size, 10)

      job = make_job(snapshot)

      assert {:cancel, "file_too_large"} = Crawler.perform(job)

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.state == :failed
      assert updated.archive_metadata["error"] =~ "file_too_large"

      assert_received {:staging_dir, staging_dir}
      refute File.exists?(staging_dir)
    end
  end
end

# Test crawler modules defined outside the test module for use in tests

defmodule Linkhut.Archiving.Workers.CrawlerTest.FailingCrawler do
  @behaviour Linkhut.Archiving.Crawler
  @behaviour Linkhut.Archiving.Crawler.Direct

  @impl true
  def source_type, do: "failing"

  @impl true
  def module_version, do: "1"

  @impl true
  def meta, do: %{tool_name: "FailingCrawler", tool_version: "0.0.1", version: module_version()}

  @impl true
  def queue, do: :crawler

  @impl true
  def accepts(_url, _meta), do: {:ok, "webpage"}

  @impl true
  def fetch(_url, _opts), do: {:error, %{msg: "simulated failure"}}
end

defmodule Linkhut.Archiving.Workers.CrawlerTest.LargeCrawler do
  @behaviour Linkhut.Archiving.Crawler
  @behaviour Linkhut.Archiving.Crawler.Direct

  @impl true
  def source_type, do: "large"

  @impl true
  def module_version, do: "1"

  @impl true
  def meta, do: %{tool_name: "LargeCrawler", tool_version: "1.0.0", version: module_version()}

  @impl true
  def queue, do: :crawler

  @impl true
  def accepts(_url, _meta), do: {:ok, "webpage"}

  @impl true
  def fetch(_url, opts) do
    staging_dir = Keyword.fetch!(opts, :staging_dir)
    send(self(), {:staging_dir, staging_dir})
    path = Path.join(staging_dir, "result")
    File.write!(path, String.duplicate("x", 1000))

    {:ok, {:file, %{path: path, response_code: 200, content_type: "application/octet-stream"}}}
  end
end

defmodule Linkhut.Archiving.Workers.CrawlerTest.SuccessCrawler do
  @behaviour Linkhut.Archiving.Crawler
  @behaviour Linkhut.Archiving.Crawler.Direct

  @impl true
  def source_type, do: "success"

  @impl true
  def module_version, do: "1"

  @impl true
  def meta, do: %{tool_name: "SuccessCrawler", tool_version: "1.0.0", version: module_version()}

  @impl true
  def queue, do: :crawler

  @impl true
  def accepts(_url, _meta), do: {:ok, "webpage"}

  @impl true
  def fetch(_url, opts) do
    path = opts |> Keyword.fetch!(:staging_dir) |> Path.join("result")
    File.write!(path, "<html>test content</html>")

    {:ok, {:file, %{path: path, response_code: 200, content_type: "text/html"}}}
  end
end

defmodule Linkhut.Archiving.Workers.CrawlerTest.RaisingCrawler do
  @behaviour Linkhut.Archiving.Crawler
  @behaviour Linkhut.Archiving.Crawler.Direct

  @impl true
  def source_type, do: "raising"

  @impl true
  def module_version, do: "1"

  @impl true
  def meta, do: %{tool_name: "RaisingCrawler", tool_version: "0.0.1", version: module_version()}

  @impl true
  def queue, do: :crawler

  @impl true
  def accepts(_url, _meta), do: {:ok, "webpage"}

  @impl true
  def fetch(_url, _opts), do: raise("kaboom!")
end

defmodule Linkhut.Archiving.Workers.CrawlerTest.NotAvailableCrawler do
  @behaviour Linkhut.Archiving.Crawler
  @behaviour Linkhut.Archiving.Crawler.External

  @impl true
  def source_type, do: "notavail"

  @impl true
  def module_version, do: "1"

  @impl true
  def meta, do: %{tool_name: "NotAvailableCrawler", tool_version: nil, version: module_version()}

  @impl true
  def queue, do: :crawler

  @impl true
  def accepts(_url), do: {:ok, "reference"}

  @impl true
  def fetch(_url, _opts), do: {:ok, :not_available}
end

defmodule Linkhut.Archiving.Workers.CrawlerTest.RateLimitedCrawler do
  @behaviour Linkhut.Archiving.Crawler
  @behaviour Linkhut.Archiving.Crawler.External

  @impl true
  def source_type, do: "ratelimited"

  @impl true
  def module_version, do: "1"

  @impl true
  def meta,
    do: %{tool_name: "RateLimitedCrawler", tool_version: nil, version: module_version()}

  @impl true
  def queue, do: :crawler

  @impl true
  def rate_limit, do: {60_000, 1}

  @impl true
  def accepts(_url), do: {:ok, "reference"}

  @impl true
  def fetch(_url, _opts), do: {:ok, :not_available}
end

defmodule Linkhut.Archiving.Workers.CrawlerTest.ExternalCrawler do
  @behaviour Linkhut.Archiving.Crawler
  @behaviour Linkhut.Archiving.Crawler.External

  @impl true
  def source_type, do: "external"

  @impl true
  def module_version, do: "1"

  @impl true
  def meta, do: %{tool_name: "ExternalCrawler", tool_version: nil, version: module_version()}

  @impl true
  def queue, do: :crawler

  @impl true
  def accepts(_url), do: {:ok, "reference"}

  @impl true
  def fetch(_url, _opts) do
    {:ok,
     {:external,
      %{url: "https://web.archive.org/web/20250301/https://example.com", response_code: 200}}}
  end
end
