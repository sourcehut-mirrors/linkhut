defmodule Linkhut.Archiving.PipelineTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{CrawlRun, Pipeline}

  defp create_crawl_run do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id, url: "https://example.com/page")

    {:ok, crawl_run} =
      Archiving.create_crawl_run(%{
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :processing
      })

    {user, link, crawl_run}
  end

  defp stub_preflight(status \\ 200, content_type \\ "text/html; charset=utf-8") do
    Req.Test.stub(Linkhut.Links.Link, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", content_type)
      |> Plug.Conn.send_resp(status, "")
    end)
  end

  describe "run/2" do
    test "full pipeline succeeds for valid HTML URL" do
      {_user, _link, crawl_run} = create_crawl_run()
      stub_preflight()

      assert {:ok, result} = Pipeline.run(crawl_run)
      assert %{crawlers: crawlers} = result
      assert crawlers != []
      names = Enum.map(crawlers, & &1.name)
      assert "singlefile" in names
    end

    test "returns not_archivable for reserved address" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      assert {:ok, %{status: :not_archivable}} = Pipeline.run(crawl_run)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :not_archivable

      step = Enum.find(updated.steps, &(&1["step"] == "not_archivable"))
      assert step["detail"]["reason"] == "reserved_address"
    end

    test "returns not_archivable for invalid URL" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "not-a-url")

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      assert {:ok, %{status: :not_archivable}} = Pipeline.run(crawl_run)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :not_archivable
    end

    test "returns not_archivable for unsupported URL scheme" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "ftp://example.com/file.txt")

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      assert {:ok, %{status: :not_archivable}} = Pipeline.run(crawl_run)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :not_archivable

      step = Enum.find(updated.steps, &(&1["step"] == "not_archivable"))
      assert step["detail"]["reason"] == "unsupported_scheme:ftp"
    end

    test "returns not_archivable for unsupported content type when no crawlers match" do
      {_user, _link, crawl_run} = create_crawl_run()
      stub_preflight(200, "image/png")

      # Only target-url crawlers — none handle image/png
      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Crawler.SingleFile
      ])

      assert {:ok, %{status: :not_archivable}} = Pipeline.run(crawl_run)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :not_archivable
    end

    test "returns not_archivable when preflight Content-Length exceeds max_file_size" do
      {_user, _link, crawl_run} = create_crawl_run()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/pdf")
        |> Plug.Conn.put_resp_header("content-length", "100000000")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, %{status: :not_archivable}} = Pipeline.run(crawl_run)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :not_archivable
    end

    test "dispatches httpfetch for PDF content" do
      {_user, _link, crawl_run} = create_crawl_run()
      stub_preflight(200, "application/pdf")

      assert {:ok, result} = Pipeline.run(crawl_run)
      names = Enum.map(result.crawlers, & &1.name)
      assert "httpfetch" in names
    end

    test "adds retry step on attempt > 1" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://nonexistent.invalid/page")

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      # Use only target-url crawlers so DNS failure isn't rescued by always-dispatch
      put_override(Linkhut.Archiving, :crawlers, [Linkhut.Archiving.Crawler.SingleFile])

      Pipeline.run(crawl_run, attempt: 2, max_attempts: 4)

      updated = Repo.get(CrawlRun, crawl_run.id)
      step_names = Enum.map(updated.steps, & &1["step"])
      assert "retry" in step_names

      retry_step = Enum.find(updated.steps, &(&1["step"] == "retry"))
      assert retry_step["detail"]["msg"] == "retry"
      assert retry_step["detail"]["attempt"] == 2
    end

    test "includes will retry in failed step when retries remain" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://nonexistent.invalid/page")

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      put_override(Linkhut.Archiving, :crawlers, [Linkhut.Archiving.Crawler.SingleFile])

      Pipeline.run(crawl_run, attempt: 1, max_attempts: 4)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :processing
      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["msg"] == "failed_will_retry"
      assert failed_step["detail"]["attempt"] == 1
      assert failed_step["detail"]["max_attempts"] == 4
    end

    test "does not include will retry in failed step on final attempt" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://nonexistent.invalid/page")

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      put_override(Linkhut.Archiving, :crawlers, [Linkhut.Archiving.Crawler.SingleFile])

      Pipeline.run(crawl_run, attempt: 4, max_attempts: 4)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :failed
      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["msg"] == "failed_final"
      assert failed_step["detail"]["attempt"] == 4
      assert failed_step["detail"]["max_attempts"] == 4
    end

    test "updates archive steps through the pipeline" do
      {_user, _link, crawl_run} = create_crawl_run()
      stub_preflight()

      {:ok, _result} = Pipeline.run(crawl_run)

      updated = Repo.get(CrawlRun, crawl_run.id)
      step_names = Enum.map(updated.steps, & &1["step"])
      assert "created" in step_names
      assert "preflight" in step_names
      assert "dispatched" in step_names
    end
  end

  describe "run/2 — only_types filtering" do
    test "only_types dispatches only matching crawlers" do
      {_user, _link, archive} = create_crawl_run()
      stub_preflight()

      assert {:ok, result} = Pipeline.run(archive, only_types: ["singlefile"])
      names = Enum.map(result.crawlers, & &1.name)
      assert names == ["singlefile"]
    end

    test "only_types with nonexistent type returns not_archivable" do
      {_user, _link, archive} = create_crawl_run()
      stub_preflight()

      assert {:ok, %{status: :not_archivable}} =
               Pipeline.run(archive, only_types: ["nonexistent"])
    end

    test "only_types nil dispatches all eligible crawlers" do
      {_user, _link, archive} = create_crawl_run()
      stub_preflight()

      assert {:ok, result} = Pipeline.run(archive, only_types: nil)
      assert result.crawlers != []
    end
  end

  describe "run/2 — third-party crawlers" do
    test "always dispatches third-party alongside target crawlers for valid HTML URL" do
      {_user, _link, crawl_run} = create_crawl_run()
      stub_preflight()

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Crawler.SingleFile,
        Linkhut.Archiving.PipelineTest.ThirdPartyCrawler
      ])

      assert {:ok, result} = Pipeline.run(crawl_run)
      names = Enum.map(result.crawlers, & &1.name)
      assert "singlefile" in names
      assert "wayback" in names
    end

    test "dispatches third-party crawler on HTTP 404 preflight" do
      {_user, _link, crawl_run} = create_crawl_run()
      stub_preflight(404, "text/html")

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Crawler.SingleFile,
        Linkhut.Archiving.PipelineTest.ThirdPartyCrawler
      ])

      assert {:ok, result} = Pipeline.run(crawl_run)
      names = Enum.map(result.crawlers, & &1.name)
      assert "wayback" in names
    end

    test "dispatches third-party crawler after DNS failure and records validation_failed step" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://nonexistent.invalid/page")

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Crawler.SingleFile,
        Linkhut.Archiving.PipelineTest.ThirdPartyCrawler
      ])

      assert {:ok, result} = Pipeline.run(crawl_run)
      names = Enum.map(result.crawlers, & &1.name)
      assert "wayback" in names
      refute "singlefile" in names

      updated = Repo.get(CrawlRun, crawl_run.id)
      step = Enum.find(updated.steps, &(&1["step"] == "validation_failed"))
      assert step["detail"]["error"] =~ "dns_failed"
    end

    test "does not dispatch third-party crawler for invalid URL (not_archivable)" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "not-a-url")

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.PipelineTest.ThirdPartyCrawler
      ])

      assert {:ok, %{status: :not_archivable}} = Pipeline.run(crawl_run)
    end

    test "dispatches wayback crawler when HEAD returns 500 with no content_type" do
      {_user, _link, crawl_run} = create_crawl_run()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:ok, result} = Pipeline.run(crawl_run)
      names = Enum.map(result.crawlers, & &1.name)
      assert "wayback" in names
    end

    test "records dns_failed as top-level error, not reserved_address" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://nonexistent.invalid/page")

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      put_override(Linkhut.Archiving, :crawlers, [])

      assert {:error, {:dns_failed, "nonexistent.invalid"}} = Pipeline.run(crawl_run)
    end

    test "dispatches third-party crawler after preflight network failure" do
      {_user, _link, crawl_run} = create_crawl_run()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.Crawler.SingleFile,
        Linkhut.Archiving.PipelineTest.ThirdPartyCrawler
      ])

      assert {:ok, result} = Pipeline.run(crawl_run)
      assert %{crawlers: [%{name: "wayback"}]} = result
    end

    test "does not dispatch third-party crawler after SSRF failure" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      put_override(Linkhut.Archiving, :crawlers, [
        Linkhut.Archiving.PipelineTest.ThirdPartyCrawler
      ])

      assert {:ok, %{status: :not_archivable}} = Pipeline.run(crawl_run)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :not_archivable
    end
  end
end

defmodule Linkhut.Archiving.PipelineTest.ThirdPartyCrawler do
  @behaviour Linkhut.Archiving.Crawler

  @impl true
  def source_type, do: "wayback"

  @impl true
  def module_version, do: "1"

  @impl true
  def meta, do: %{tool_name: "ThirdPartyCrawler", tool_version: nil, version: module_version()}

  @impl true
  def network_access, do: :third_party

  @impl true
  def queue, do: :crawler

  @impl true
  def can_handle?(url, _meta) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> true
      _ -> false
    end
  end

  @impl true
  def fetch(_context) do
    {:ok, {:external, %{url: "https://external.example.com/snapshot", response_code: 200}}}
  end
end
