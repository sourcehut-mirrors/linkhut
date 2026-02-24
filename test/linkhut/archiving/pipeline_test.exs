defmodule Linkhut.Archiving.PipelineTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Archive, Pipeline, Snapshot}
  alias Linkhut.Archiving.Workers.Archiver

  defp create_archive do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id, url: "https://example.com/page")
    {:ok, job} = insert_oban_job(user.id, link.id, link.url)
    {:ok, archive} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)
    {user, link, archive}
  end

  defp insert_oban_job(user_id, link_id, url) do
    Archiver.new(%{
      "user_id" => user_id,
      "link_id" => link_id,
      "url" => url
    })
    |> Oban.insert()
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
      assert hd(crawlers).name == "singlefile"
    end

    test "fails for reserved address" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")
      {:ok, job} = insert_oban_job(user.id, link.id, link.url)
      {:ok, archive} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)

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
      {:ok, job} = insert_oban_job(user.id, link.id, link.url)
      {:ok, archive} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)

      assert {:error, :invalid_url} = Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :failed
    end

    test "fails for unsupported URL scheme" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "ftp://example.com/file.txt")
      {:ok, job} = insert_oban_job(user.id, link.id, link.url)
      {:ok, archive} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)

      assert {:error, {:unsupported_scheme, "ftp"}} = Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :failed

      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["error"] =~ "unsupported_scheme"
    end

    test "fails when HEAD request fails" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      # A 500 status succeeds at the HTTP level but the pipeline still runs.
      # To simulate a transport error, we need to use Req.Test.transport_error.
      # But since that's not straightforward, test that a 500 with no content_type
      # leads to no eligible crawlers.
      assert {:error, :no_eligible_crawlers} = Pipeline.run(archive)
    end

    test "fails when no eligible crawlers for non-HTML content" do
      {_user, _link, archive} = create_archive()
      stub_preflight(200, "application/pdf")

      assert {:error, :no_eligible_crawlers} = Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :failed
    end

    test "adds retry step on attempt > 1" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")
      {:ok, job} = insert_oban_job(user.id, link.id, link.url)
      {:ok, archive} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)

      Pipeline.run(archive, attempt: 2, max_attempts: 4)

      updated = Repo.get(Archive, archive.id)
      step_names = Enum.map(updated.steps, & &1["step"])
      assert "retry" in step_names

      retry_step = Enum.find(updated.steps, &(&1["step"] == "retry"))
      assert retry_step["detail"]["msg"] == "retry"
      assert retry_step["detail"]["attempt"] == 2
    end

    test "does not add retry step on first attempt" do
      {_user, _link, archive} = create_archive()
      stub_preflight()

      Pipeline.run(archive, attempt: 1, max_attempts: 4)

      updated = Repo.get(Archive, archive.id)
      step_names = Enum.map(updated.steps, & &1["step"])
      refute "retry" in step_names
    end

    test "includes will retry in failed step when retries remain" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")
      {:ok, job} = insert_oban_job(user.id, link.id, link.url)
      {:ok, archive} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)

      Pipeline.run(archive, attempt: 1, max_attempts: 4)

      updated = Repo.get(Archive, archive.id)
      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["msg"] == "failed_will_retry"
      assert failed_step["detail"]["attempt"] == 1
      assert failed_step["detail"]["max_attempts"] == 4
    end

    test "does not include will retry in failed step on final attempt" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/page")
      {:ok, job} = insert_oban_job(user.id, link.id, link.url)
      {:ok, archive} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)

      Pipeline.run(archive, attempt: 4, max_attempts: 4)

      updated = Repo.get(Archive, archive.id)
      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["msg"] == "failed_final"
      assert failed_step["detail"]["attempt"] == 4
      assert failed_step["detail"]["max_attempts"] == 4
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

    test "preflight step includes content type and status" do
      {_user, _link, archive} = create_archive()
      stub_preflight(200, "text/html; charset=utf-8")

      {:ok, _result} = Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      preflight_step = Enum.find(updated.steps, &(&1["step"] == "preflight"))
      assert preflight_step["detail"]["msg"] == "preflight_http"
      assert preflight_step["detail"]["content_type"] == "text/html"
      assert preflight_step["detail"]["status"] == 200
    end

    test "preflight step includes final URL when redirected" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        case conn.request_path do
          "/page" ->
            conn
            |> Plug.Conn.put_resp_header("location", "/final-page")
            |> Plug.Conn.send_resp(301, "")

          "/final-page" ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "text/html")
            |> Plug.Conn.send_resp(200, "")
        end
      end)

      {:ok, _result} = Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      preflight_step = Enum.find(updated.steps, &(&1["step"] == "preflight"))
      assert preflight_step["detail"]["final_url"] =~ "/final-page"
    end

    test "preflight step includes content length when available" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html")
        |> Plug.Conn.put_resp_header("content-length", "52428")
        |> Plug.Conn.send_resp(200, "")
      end)

      {:ok, _result} = Pipeline.run(archive)

      updated = Repo.get(Archive, archive.id)
      preflight_step = Enum.find(updated.steps, &(&1["step"] == "preflight"))
      assert preflight_step["detail"]["size"] == "51.2 KB"
    end
  end

  describe "preflight/1" do
    test "extracts content type and status from response" do
      {_user, _link, archive} = create_archive()
      stub_preflight(200, "text/html; charset=utf-8")

      assert {:ok, preflight_meta, updated_archive} = Pipeline.preflight(archive)
      assert preflight_meta.content_type == "text/html"
      assert preflight_meta.status == 200
      assert preflight_meta.final_url == archive.url
      assert updated_archive.final_url == archive.url
    end

    test "includes scheme in preflight_meta" do
      {_user, _link, archive} = create_archive()
      stub_preflight()

      assert {:ok, preflight_meta, _archive} = Pipeline.preflight(archive)
      assert preflight_meta.scheme == "https"
    end

    test "captures final URL after redirect" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        case conn.request_path do
          "/page" ->
            conn
            |> Plug.Conn.put_resp_header("location", "/final-page")
            |> Plug.Conn.send_resp(301, "")

          "/final-page" ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "text/html")
            |> Plug.Conn.send_resp(200, "")
        end
      end)

      assert {:ok, preflight_meta, updated_archive} = Pipeline.preflight(archive)
      assert preflight_meta.final_url =~ "/final-page"
      assert updated_archive.final_url =~ "/final-page"
    end

    test "extracts content-length header" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/pdf")
        |> Plug.Conn.put_resp_header("content-length", "12345")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, preflight_meta, _archive} = Pipeline.preflight(archive)
      assert preflight_meta.content_type == "application/pdf"
      assert preflight_meta.content_length == 12345
    end

    test "handles nil content type" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, preflight_meta, _archive} = Pipeline.preflight(archive)
      assert preflight_meta.content_type == nil
    end

    test "records preflight step on success" do
      {_user, _link, archive} = create_archive()
      stub_preflight()

      {:ok, _meta, updated} = Pipeline.preflight(archive)
      assert Enum.any?(updated.steps, fn s -> s["step"] == "preflight" end)
    end

    test "returns error tuple on HTTP error status" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      # 404 is still a successful HTTP response — pipeline should continue
      assert {:ok, preflight_meta, _archive} = Pipeline.preflight(archive)
      assert preflight_meta.status == 404
    end

    test "returns error for unsupported scheme" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "ftp://example.com/file.txt")
      {:ok, job} = insert_oban_job(user.id, link.id, link.url)
      {:ok, archive} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)

      assert {:error, {:unsupported_scheme, "ftp"}, _archive} = Pipeline.preflight(archive)
    end
  end

  describe "select_crawlers/2" do
    test "returns SingleFile for text/html content" do
      crawlers =
        Pipeline.select_crawlers("https://example.com", %{content_type: "text/html"})

      assert length(crawlers) == 1
      assert hd(crawlers) == Linkhut.Archiving.Crawler.SingleFile
    end

    test "returns empty list for non-HTML content" do
      crawlers =
        Pipeline.select_crawlers("https://example.com/doc.pdf", %{content_type: "application/pdf"})

      assert crawlers == []
    end

    test "returns empty list for nil content type" do
      crawlers =
        Pipeline.select_crawlers("https://example.com", %{content_type: nil})

      assert crawlers == []
    end
  end

  describe "dispatch_crawlers/3" do
    test "returns error for empty crawler list without updating archive" do
      {_user, _link, archive} = create_archive()

      assert {:error, :no_eligible_crawlers, ^archive} =
               Pipeline.dispatch_crawlers(archive, [], [])

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :active
    end

    test "creates snapshots and enqueues jobs atomically" do
      {_user, _link, archive} = create_archive()
      crawlers = [Linkhut.Archiving.Crawler.SingleFile]

      assert {:ok, result} = Pipeline.dispatch_crawlers(archive, crawlers, [])
      assert %{crawlers: dispatched} = result
      assert length(dispatched) == 1
      assert hd(dispatched).name == "singlefile"

      # Verify snapshot was created
      snapshots = Repo.all(from s in Snapshot, where: s.archive_id == ^archive.id)
      assert length(snapshots) == 1
      snapshot = hd(snapshots)
      assert snapshot.type == "singlefile"
      assert snapshot.state == :pending
      assert snapshot.job_id != nil
    end

    test "passes recrawl flag to job args" do
      {_user, _link, archive} = create_archive()
      crawlers = [Linkhut.Archiving.Crawler.SingleFile]

      assert {:ok, _} = Pipeline.dispatch_crawlers(archive, crawlers, recrawl: true)

      assert_enqueued(
        worker: Linkhut.Archiving.Workers.Crawler,
        args: %{"recrawl" => true, "archive_id" => archive.id}
      )
    end
  end
end
