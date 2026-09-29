defmodule Linkhut.Archiving.Workers.ArchiverTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving.{CrawlRun, LinkArchival, Snapshot}
  alias Linkhut.Archiving.Workers.Archiver
  alias Linkhut.Archiving.Workers.Crawler, as: CrawlerWorker

  describe "enqueue/2" do
    test "opens a run with its job, records the crawlers it will attempt, and logs it" do
      link = insert_link("https://example.com/page")

      assert {:ok, %Oban.Job{conflict?: false} = job} = Archiver.enqueue(link)

      assert [run] = Repo.all(CrawlRun)
      assert run.link_id == link.id

      assert job.args == %{
               crawl_run_id: run.id,
               link_id: link.id,
               recrawl: false
             }

      assert archivals(link) == [
               {"httpfetch", "1", run.id, nil},
               {"singlefile", "1", run.id, nil},
               {"wayback", "1", run.id, nil}
             ]

      assert [%{event: "run.created", data: data}] = events(run)
      assert data == %{}
    end

    test "opens nothing when an equivalent job is already queued" do
      link = insert_link("https://example.com/page")

      assert {:ok, first} = Archiver.enqueue(link, recrawl: true)
      assert {:ok, %Oban.Job{conflict?: true} = second} = Archiver.enqueue(link, recrawl: true)

      assert second.id == first.id
      assert [run] = Repo.all(CrawlRun)
      assert [%{event: "run.created"}] = events(run)
      assert link |> archivals() |> Enum.map(&elem(&1, 2)) == [run.id, run.id, run.id]
    end

    test "re-runs a crawler when its version changes" do
      link = insert_link("https://example.com/page")
      archived(link, %{"singlefile" => "0", "httpfetch" => "1", "wayback" => "1"})

      assert {:ok, job} = Archiver.enqueue(link)

      assert [
               {"httpfetch", "1", nil, nil},
               {"singlefile", "1", run_id, nil},
               {"wayback", "1", nil, nil}
             ] = archivals(link)

      assert run_id == job.args.crawl_run_id
    end

    test "recrawl retries the given crawlers, or every applicable one if none given" do
      link = insert_link("https://example.com/page")
      archived(link, %{"singlefile" => "1", "httpfetch" => "1", "wayback" => "1"})

      assert {:ok, job} = Archiver.enqueue(link, recrawl: true, only_types: ["singlefile"])
      run_id = job.args.crawl_run_id

      assert [{"httpfetch", _, nil, _}, {"singlefile", _, ^run_id, _}, {"wayback", _, nil, _}] =
               archivals(link)

      Repo.update_all(Oban.Job, set: [state: "completed"])

      assert {:ok, job} = Archiver.enqueue(link, recrawl: true)
      run_id = job.args.crawl_run_id
      assert link |> archivals() |> Enum.map(&elem(&1, 2)) == [run_id, run_id, run_id]
    end

    test "doesn't re-attempt an unsuccessful crawler if it's still at the same version" do
      link = insert_link("https://example.com/page")
      stub_preflight(404)

      {job, run} = enqueue_link(link)
      assert :ok = perform(job, attempt: 1)
      assert sources(run) == ["wayback"]
      Repo.update_all(Oban.Job, set: [state: "completed"])

      assert {:ok, :nothing_to_archive} = Archiver.enqueue(link)

      Repo.update_all(from(s in Snapshot, where: s.link_id == ^link.id), set: [state: :failed])
      assert {:ok, :nothing_to_archive} = Archiver.enqueue(link)

      Repo.delete_all(from(s in Snapshot, where: s.link_id == ^link.id))
      assert link |> archivals() |> Enum.map(&elem(&1, 3)) == [nil, nil, nil]
      assert {:ok, :nothing_to_archive} = Archiver.enqueue(link)
    end
  end

  describe "perform/1" do
    test "dispatches external crawlers, then direct crawlers that accept the preflight" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        case conn.request_path do
          "/page" ->
            conn
            |> Plug.Conn.put_resp_header("location", "/final-page")
            |> Plug.Conn.send_resp(301, "")

          "/final-page" ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "text/html; charset=utf-8")
            |> Plug.Conn.send_resp(200, "")
        end
      end)

      crawl_run = archive("https://example.com/page")

      assert sources(crawl_run) == ["singlefile", "wayback"]

      assert event_names(crawl_run) == [
               "run.created",
               "run.started",
               "crawler.dispatched",
               "preflight.completed",
               "crawler.dispatched",
               "crawler.skipped"
             ]

      assert [%{source: "wayback"}, %{source: "singlefile"}] =
               Enum.filter(events(crawl_run), &(&1.event == "crawler.dispatched"))

      assert %{source: "httpfetch", data: %{"reason" => "unsupported_format"}} =
               find_event(crawl_run, "crawler.skipped")

      assert find_event(crawl_run, "preflight.completed").data == %{
               "url" => "https://example.com/page",
               "final_url" => "https://example.com/final-page",
               "method" => "HEAD",
               "scheme" => "https",
               "content_type" => "text/html",
               "status" => 200
             }

      ids = crawl_run |> snapshots() |> Map.new(&{&1.source, &1.id})

      expected = [
        %{
          "snapshot_id" => ids["wayback"],
          "crawl_run_id" => crawl_run.id,
          "url" => "https://example.com/page"
        },
        %{
          "snapshot_id" => ids["singlefile"],
          "crawl_run_id" => crawl_run.id,
          "url" => "https://example.com/final-page"
        }
      ]

      assert all_enqueued(worker: CrawlerWorker)
             |> Enum.map(& &1.args)
             |> Enum.sort_by(& &1["snapshot_id"]) == Enum.sort_by(expected, & &1["snapshot_id"])
    end

    test "stores the format each crawler accepted with" do
      stub_preflight(200, "application/pdf")

      crawl_run = archive("https://example.com/doc.pdf")

      assert crawl_run
             |> snapshots()
             |> Enum.map(&{&1.source, &1.format}) == [
               {"httpfetch", "pdf"},
               {"wayback", "reference"}
             ]
    end

    test "a redirect to a private address skips direct crawlers only" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        case conn.host do
          "example.com" ->
            conn
            |> Plug.Conn.put_resp_header("location", "http://127.0.0.1/admin")
            |> Plug.Conn.send_resp(302, "")

          _ ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "text/html")
            |> Plug.Conn.send_resp(200, "")
        end
      end)

      crawl_run = archive("https://example.com/page")

      assert sources(crawl_run) == ["wayback"]

      assert %{data: %{"reason" => "reserved_address", "host" => "127.0.0.1"}} =
               Enum.find(events(crawl_run), &(&1.source == "singlefile"))

      assert %{level: :warning, data: blocked} = find_event(crawl_run, "preflight.blocked")

      assert blocked == %{
               "reason" => "reserved_address",
               "host" => "127.0.0.1",
               "range" => "loopback",
               "redirect" => "http://127.0.0.1/admin",
               "url" => "https://example.com/page"
             }
    end

    test "a URL that can't be archived dispatches nothing" do
      crawl_run = archive("http://localhost/page")
      assert sources(crawl_run) == []
      assert length(archivals(crawl_run.link_id)) == 3

      assert %{level: :error, data: data} = find_event(crawl_run, "run.not_archivable")

      assert data == %{
               "reason" => "reserved_address",
               "host" => "localhost",
               "range" => "loopback"
             }
    end
  end

  describe "perform/1 when the site can't be reached" do
    test "a failed preflight is retried, and the retry does not dispatch again" do
      Req.Test.stub(Linkhut.Links.Link, &Req.Test.transport_error(&1, :econnrefused))

      {job, crawl_run} = enqueue("https://example.com/page")

      assert {:error, _reason} = perform(job, attempt: 1)
      assert sources(crawl_run) == ["wayback"]

      assert %{level: :warning, data: %{"url" => "https://example.com/page", "error" => _}} =
               find_event(crawl_run, "preflight.failed")

      stub_preflight()

      assert :ok = perform(job, attempt: 2)
      assert sources(crawl_run) == ["singlefile", "wayback"]
      assert %{data: %{"attempt" => 2}} = find_event(crawl_run, "run.retried")
      assert length(all_enqueued(worker: CrawlerWorker)) == 2
    end

    test "a DNS failure on the last attempt fails the run, and keeps its rows" do
      {job, crawl_run} = enqueue("http://nonexistent.invalid/page")
      run_id = crawl_run.id

      assert {:error, {:dns_failed, _}} = perform(job, attempt: 1)
      refute find_event(crawl_run, "run.failed")

      assert {:error, {:dns_failed, _}} = perform(job, attempt: 4)
      assert sources(crawl_run) == ["wayback"]

      assert [
               {"httpfetch", "1", ^run_id, nil},
               {"singlefile", "1", ^run_id, nil},
               {"wayback", "1", ^run_id, _snapshot_id}
             ] = archivals(crawl_run.link_id)

      assert %{level: :warning, data: %{"error" => error}} =
               find_event(crawl_run, "run.url_check_failed")

      assert error =~ "dns_failed"

      assert %{level: :error, data: %{"attempt" => 4, "max_attempts" => 4}} =
               find_event(crawl_run, "run.failed")
    end
  end

  describe "perform/1 on a stale job" do
    test "leaves a run alone once a re-archive has taken over its rows" do
      link = insert_link("https://example.com/page")
      {job, crawl_run} = enqueue_link(link)
      {_job, _recrawl} = enqueue_link(link, recrawl: true)

      assert :ok = perform(job, attempt: 1)

      assert event_names(crawl_run) == ["run.created"]
      assert all_enqueued(worker: CrawlerWorker) == []
    end
  end

  defp events(run), do: Repo.preload(run, :events, force: true).events

  defp enqueue(url), do: url |> insert_link() |> enqueue_link()

  defp enqueue_link(link, opts \\ []) do
    {:ok, job} = Archiver.enqueue(link, opts)
    {job, Repo.get(CrawlRun, job.args.crawl_run_id)}
  end

  defp insert_link(url) do
    user = insert(:user, credential: build(:credential))
    insert(:link, user_id: user.id, url: url)
  end

  defp archived(link, versions) do
    for {source, version} <- versions do
      insert(:link_archival, link_id: link.id, source: source, version: version)
    end
  end

  defp archivals(%Linkhut.Links.Link{id: link_id}), do: archivals(link_id)

  defp archivals(link_id) do
    Repo.all(
      from a in LinkArchival,
        where: a.link_id == ^link_id,
        order_by: a.source,
        select: {a.source, a.version, a.crawl_run_id, a.snapshot_id}
    )
  end

  defp archive(url) do
    {job, crawl_run} = enqueue(url)
    :ok = perform(job, attempt: 1)
    crawl_run
  end

  defp perform(job, opts), do: perform_job(Archiver, job.args, opts)

  defp stub_preflight(status \\ 200, content_type \\ "text/html") do
    Req.Test.stub(Linkhut.Links.Link, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", content_type)
      |> Plug.Conn.send_resp(status, "")
    end)
  end

  defp snapshots(crawl_run) do
    Repo.all(from s in Snapshot, where: s.link_id == ^crawl_run.link_id, order_by: s.source)
  end

  defp sources(crawl_run), do: Enum.map(snapshots(crawl_run), & &1.source)

  defp event_names(crawl_run), do: Enum.map(events(crawl_run), & &1.event)

  defp find_event(crawl_run, name), do: Enum.find(events(crawl_run), &(&1.event == name))
end
