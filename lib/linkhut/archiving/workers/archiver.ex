defmodule Linkhut.Archiving.Workers.Archiver do
  @moduledoc """
  Archives a link:

  1. check the URL
  2. dispatch the external crawlers that accept it
  3. make the preflight request, if there are direct crawlers
  4. dispatch the direct crawlers that accept the preflight's result

  When retrying it should only dispatch crawlers that haven't been dispatched yet.
  """

  use Oban.Worker,
    queue: :archiver,
    # Initial attempt + 3 retries
    max_attempts: 4,
    unique: [
      period: {1, :hour},
      keys: [:link_id, :recrawl],
      states: :incomplete
    ]

  import Ecto.Query

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Crawler, CrawlRun, LinkArchival, Log, Snapshot}
  alias Linkhut.Archiving.Preflight.HTTP, as: Preflight
  alias Linkhut.Archiving.Workers.Crawler, as: CrawlerWorker
  alias Linkhut.Links.Link
  alias Linkhut.Repo

  @doc """
  Initiates a crawl run for `link`, enqueues the Oban job and records the
  crawlers that will be launched.

  By default, only crawlers that apply to the link URL and haven't yet
  attempted it will be launched, but with `:recrawl` all applicable crawlers
  will be launched.

  ## Options

    - `:recrawl`: attempt the crawlers even if they have already archived the
      link at their current version.
    - `:only_types`: (only read when `recrawl: true`) it filters the crawlers
      that will be launched to the provided types
  """
  @spec enqueue(Link.t(), keyword()) ::
          {:ok, Oban.Job.t() | :nothing_to_archive} | {:error, term()}
  def enqueue(%Link{} = link, opts \\ []) do
    case crawlers_to_archive(link, opts) do
      [] -> {:ok, :nothing_to_archive}
      crawlers -> open_run(link, crawlers, opts)
    end
  end

  defp crawlers_to_archive(link, opts) do
    if opts[:recrawl] do
      types = opts[:only_types]

      link
      |> LinkArchival.applicable_crawlers()
      |> Enum.filter(&(is_nil(types) or &1.source_type() in types))
    else
      LinkArchival.due_crawlers(link)
    end
  end

  defp open_run(link, crawlers, opts) do
    case Repo.transact(fn -> insert_run(link, crawlers, opts) end) do
      {:ok, {run, job}} ->
        data = %{recrawl: opts[:recrawl] || nil, only_types: opts[:only_types]}
        run.id |> Log.for_run() |> Log.append("run.created", data)
        {:ok, job}

      {:error, {:already_queued, job}} ->
        {:ok, job}

      {:error, _} = error ->
        error
    end
  end

  defp insert_run(link, crawlers, opts) do
    with {:ok, run} <- Repo.insert(%CrawlRun{link_id: link.id}),
         {:ok, job} <-
           %{
             crawl_run_id: run.id,
             link_id: run.link_id,
             recrawl: opts[:recrawl] == true
           }
           |> new()
           |> Oban.insert() do
      if job.conflict?, do: Repo.rollback({:already_queued, job})
      record_attempts(run, crawlers)
      {:ok, {run, job}}
    end
  end

  defp record_attempts(run, crawlers) do
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(crawlers, fn crawler ->
        %{
          link_id: run.link_id,
          source: crawler.source_type(),
          version: crawler.module_version(),
          crawl_run_id: run.id,
          snapshot_id: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(LinkArchival, rows,
      on_conflict: {:replace, [:version, :crawl_run_id, :snapshot_id, :updated_at]},
      conflict_target: [:link_id, :source]
    )
  end

  @backoff_seconds [60, 300, 1_800]

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    @backoff_seconds
    |> Enum.at(attempt - 1, List.last(@backoff_seconds))
    |> Oban.Backoff.jitter(mode: :inc)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"crawl_run_id" => run_id, "link_id" => link_id}} = job) do
    with %Link{} = link <- Repo.get_by(Link, id: link_id),
         [_ | _] = crawlers <- undispatched(run_id) do
      log = Log.for_run(run_id)
      log_start(log, job.attempt)

      crawlers
      |> Enum.split_with(&Crawler.external?/1)
      |> then(&archive(link, log, &1))
      |> finish(log, job)
    else
      _gone_or_done -> :ok
    end
  end

  defp undispatched(run_id) do
    sources =
      from(a in LinkArchival,
        where: a.crawl_run_id == ^run_id and is_nil(a.snapshot_id),
        select: a.source
      )
      |> Repo.all()

    Linkhut.Config.archiving(:crawlers, [])
    |> Enum.filter(&(&1.source_type() in sources))
  end

  defp log_start(log, 1), do: Log.append(log, "run.started")
  defp log_start(log, n), do: Log.append(log, "run.retried", %{attempt: n})

  defp archive(link, log, {external, direct}) do
    case check_url(link, log) do
      {:unusable, _reason} = unusable ->
        unusable

      url_check ->
        dispatch(link, log, link.url, external, & &1.accepts(link.url))

        with [_ | _] <- direct,
             :ok <- url_check,
             {:ok, meta} <- Preflight.execute(link.url, log: log) do
          dispatch(link, log, meta.final_url, direct, & &1.accepts(meta.final_url, meta))
        else
          [] ->
            :ok

          {:unusable, reason} ->
            Enum.each(direct, &skip(log, &1, reason))
            :ok

          {:unreachable, _reason} = unreachable ->
            unreachable
        end
    end
  end

  defp check_url(link, log) do
    with {:unreachable, reason} = unreachable <- Preflight.check_url(link.url) do
      Log.append(log, "run.url_check_failed", %{url: link.url, error: inspect(reason)},
        level: :warning
      )

      unreachable
    end
  end

  defp dispatch(link, log, url, crawlers, accepts) do
    Enum.each(crawlers, fn crawler ->
      case accepts.(crawler) do
        {:ok, format} -> dispatch_crawler(link, log, url, crawler, format)
        {:reject, reason} -> skip(log, crawler, reason)
      end
    end)
  end

  defp dispatch_crawler(link, %Log{crawl_run_id: run_id}, url, crawler, format) do
    Repo.transact(fn ->
      with {:ok, snapshot} <-
             %Snapshot{link_id: link.id, user_id: link.user_id}
             |> Snapshot.create_changeset(%{
               format: format,
               source: crawler.source_type(),
               crawler_meta: crawler.meta()
             })
             |> Repo.insert(),
           {:ok, job} <-
             CrawlerWorker.enqueue(snapshot, run_id, url, queue: to_string(crawler.queue())),
           {:ok, snapshot} <- Archiving.update_snapshot(snapshot, %{job_id: job.id}),
           {1, _} <- claim_archival(run_id, snapshot) do
        {:ok, snapshot}
      else
        {0, _} -> Repo.rollback(:already_dispatched)
        error -> error
      end
    end)
    |> case do
      {:ok, snapshot} -> snapshot |> Log.for_snapshot(run_id) |> Log.append("crawler.dispatched")
      {:error, :already_dispatched} -> :ok
    end
  end

  defp claim_archival(run_id, snapshot) do
    from(a in LinkArchival,
      where:
        a.link_id == ^snapshot.link_id and a.source == ^snapshot.source and
          a.crawl_run_id == ^run_id and is_nil(a.snapshot_id)
    )
    |> Repo.update_all(set: [snapshot_id: snapshot.id])
  end

  defp skip(log, crawler, reason) do
    Log.append(log, "crawler.skipped", reason, source: crawler.source_type())
  end

  defp finish({:unreachable, reason}, _log, %Oban.Job{attempt: attempt, max_attempts: max})
       when attempt < max,
       do: {:error, reason}

  defp finish(:ok, _log, _job), do: :ok

  defp finish({:unusable, reason}, log, _job) do
    Log.append(log, "run.not_archivable", reason, level: :error)
    :ok
  end

  defp finish({:unreachable, reason}, log, job) do
    data = %{error: inspect(reason), attempt: job.attempt, max_attempts: job.max_attempts}
    Log.append(log, "run.failed", data, level: :error)
    {:error, reason}
  end
end
