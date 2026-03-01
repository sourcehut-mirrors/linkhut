defmodule Linkhut.Archiving.PipelineTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Archive, Pipeline}

  defp create_archive do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id, url: "https://example.com/page")

    {:ok, archive} =
      Archiving.create_archive(%{
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :processing
      })

    {user, link, archive}
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
      {_user, _link, archive} = create_archive()
      stub_preflight()

      assert {:ok, result} = Pipeline.run(archive)
      assert %{crawlers: crawlers} = result
      assert crawlers != []
      names = Enum.map(crawlers, & &1.name)
      assert "singlefile" in names
    end

    test "fails for reserved address" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      assert {:error, {:reserved_address, {:reserved, :loopback, "localhost"}}} =
               Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :failed

      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["msg"] == "failed_final"
      assert failed_step["detail"]["attempt"] == 1
    end

    test "fails for invalid URL" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "not-a-url")

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      assert {:error, :invalid_url} = Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :failed
    end

    test "fails for unsupported URL scheme" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "ftp://example.com/file.txt")

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      assert {:error, {:unsupported_scheme, "ftp"}} = Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :failed

      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["error"] =~ "unsupported_scheme"
    end

    test "dispatches wayback crawler when HEAD returns 500 with no content_type" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      # No target crawlers match (no content_type), but Wayback Machine (third-party) does
      assert {:ok, result} = Pipeline.run(archive)
      names = Enum.map(result.crawlers, & &1.name)
      assert "wayback" in names
    end

    test "dispatches only httpfetch for PDF content" do
      {_user, _link, archive} = create_archive()
      stub_preflight(200, "application/pdf")

      assert {:ok, result} = Pipeline.run(archive)
      names = Enum.map(result.crawlers, & &1.name)
      assert names == ["httpfetch"]
    end

    test "fails for unsupported content type with 200 status" do
      {_user, _link, archive} = create_archive()
      stub_preflight(200, "image/png")

      assert {:error, :no_eligible_crawlers} = Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :failed
    end

    test "adds retry step on attempt > 1" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      Pipeline.run(archive, attempt: 2, max_attempts: 4)

      updated = Repo.get(Archive, archive.id)
      step_names = Enum.map(updated.steps, & &1["step"])
      assert "retry" in step_names

      retry_step = Enum.find(updated.steps, &(&1["step"] == "retry"))
      assert retry_step["detail"]["msg"] == "retry"
      assert retry_step["detail"]["attempt"] == 2
    end

    test "includes will retry in failed step when retries remain" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      Pipeline.run(archive, attempt: 1, max_attempts: 4)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :processing
      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["msg"] == "failed_will_retry"
      assert failed_step["detail"]["attempt"] == 1
      assert failed_step["detail"]["max_attempts"] == 4
    end

    test "does not include will retry in failed step on final attempt" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      Pipeline.run(archive, attempt: 4, max_attempts: 4)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :failed
      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["msg"] == "failed_final"
      assert failed_step["detail"]["attempt"] == 4
      assert failed_step["detail"]["max_attempts"] == 4
    end

    test "fails when preflight Content-Length exceeds max_file_size" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/pdf")
        |> Plug.Conn.put_resp_header("content-length", "100000000")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:error, {:file_too_large, 100_000_000}} = Pipeline.run(archive)
    end

    test "updates archive steps through the pipeline" do
      {_user, _link, archive} = create_archive()
      stub_preflight()

      {:ok, _result} = Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      step_names = Enum.map(updated.steps, & &1["step"])
      assert "created" in step_names
      assert "preflight" in step_names
      assert "dispatched" in step_names
    end
  end

  describe "run/2 — third-party crawlers" do
    test "does not dispatch third-party crawler after SSRF failure" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      set_crawlers([Linkhut.Archiving.PipelineTest.ThirdPartyCrawler])

      assert {:error, {:reserved_address, _}} = Pipeline.run(archive)
    end

    test "dispatches third-party crawler after preflight network failure" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      set_crawlers([
        Linkhut.Archiving.Crawler.SingleFile,
        Linkhut.Archiving.PipelineTest.ThirdPartyCrawler
      ])

      assert {:ok, result} = Pipeline.run(archive)
      assert %{crawlers: [%{name: "thirdparty"}]} = result
    end

    test "dispatches third-party crawler on HTTP error status" do
      {_user, _link, archive} = create_archive()
      stub_preflight(404, "text/html")

      set_crawlers([
        Linkhut.Archiving.Crawler.SingleFile,
        Linkhut.Archiving.PipelineTest.ThirdPartyCrawler
      ])

      assert {:ok, result} = Pipeline.run(archive)
      names = Enum.map(result.crawlers, & &1.name)
      assert "thirdparty" in names
      refute "singlefile" in names
    end

    test "dispatches third-party crawler after DNS failure" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://nonexistent.invalid/page")

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      set_crawlers([
        Linkhut.Archiving.Crawler.SingleFile,
        Linkhut.Archiving.PipelineTest.ThirdPartyCrawler
      ])

      assert {:ok, result} = Pipeline.run(archive)
      names = Enum.map(result.crawlers, & &1.name)
      assert "thirdparty" in names
      refute "singlefile" in names
    end

    test "records dns_failed as top-level error, not reserved_address" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://nonexistent.invalid/page")

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      set_crawlers([])

      assert {:error, {:dns_failed, "nonexistent.invalid"}} = Pipeline.run(archive)
    end

    test "does not dispatch third-party crawler on successful preflight" do
      {_user, _link, archive} = create_archive()
      stub_preflight()

      set_crawlers([
        Linkhut.Archiving.Crawler.SingleFile,
        Linkhut.Archiving.PipelineTest.ThirdPartyCrawler
      ])

      assert {:ok, result} = Pipeline.run(archive)
      names = Enum.map(result.crawlers, & &1.name)
      assert names == ["singlefile"]
    end
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

defmodule Linkhut.Archiving.PipelineTest.ThirdPartyCrawler do
  @behaviour Linkhut.Archiving.Crawler

  @impl true
  def type, do: "thirdparty"

  @impl true
  def meta, do: %{tool_name: "ThirdPartyCrawler", version: nil}

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
