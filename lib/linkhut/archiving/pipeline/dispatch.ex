defmodule Linkhut.Archiving.Pipeline.Dispatch do
  @moduledoc """
  Builds and executes the Ecto.Multi transaction that atomically creates
  pending snapshots and enqueues crawler jobs.
  """

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{CrawlRun, Steps}
  alias Linkhut.Links.Link
  alias Linkhut.Repo
  alias Linkhut.Archiving.Workers.Crawler, as: CrawlerWorker

  @doc """
  Atomically creates pending snapshots and enqueues Crawler jobs.
  Uses Repo.transaction + Oban.insert_all for atomicity.
  """
  @spec dispatch_crawlers(CrawlRun.t(), [module()], keyword()) ::
          {:ok, map()} | {:error, term(), CrawlRun.t()}
  def dispatch_crawlers(_crawl_run, [], _opts) do
    raise ArgumentError, "dispatch_crawlers/3 called with empty crawler list"
  end

  def dispatch_crawlers(%CrawlRun{} = crawl_run, crawlers, opts) when is_list(crawlers) do
    indexed_crawlers = Enum.with_index(crawlers)
    preflight_meta = crawl_run.preflight_meta
    link_inserted_at = get_link_inserted_at(crawl_run.link_id)

    multi =
      indexed_crawlers
      |> Enum.reduce(Ecto.Multi.new(), fn {crawler_module, idx}, multi ->
        build_crawler_steps(
          multi,
          crawl_run,
          crawler_module,
          idx,
          preflight_meta,
          link_inserted_at,
          opts
        )
      end)
      |> Ecto.Multi.run(:update_crawl_run, fn _repo, _changes ->
        crawler_names = Enum.map_join(crawlers, ", ", & &1.type())

        Archiving.update_crawl_run(crawl_run, %{
          steps:
            Steps.append_step(crawl_run.steps, "dispatched", %{
              "msg" => "dispatched",
              "crawlers" => crawler_names
            })
        })
      end)

    case Repo.transaction(multi) do
      {:ok, changes} ->
        {:ok,
         %{
           timestamp: DateTime.utc_now(),
           crawlers:
             Enum.map(indexed_crawlers, fn {mod, idx} ->
               job = changes[{:job, idx}]
               %{name: mod.type(), job_id: job.id}
             end)
         }}

      {:error, _step, reason, _changes} ->
        {:error, reason, crawl_run}
    end
  end

  defp build_crawler_steps(
         multi,
         crawl_run,
         crawler_module,
         idx,
         preflight_meta,
         link_inserted_at,
         opts
       ) do
    type = crawler_module.type()

    multi
    |> Ecto.Multi.run({:snapshot, idx}, fn _repo, _changes ->
      Archiving.create_snapshot(crawl_run.link_id, crawl_run.user_id, %{
        crawl_run_id: crawl_run.id,
        type: type,
        state: :pending,
        crawler_meta: crawler_module.meta()
      })
    end)
    |> Oban.insert({:job, idx}, fn changes ->
      snapshot = changes[{:snapshot, idx}]

      CrawlerWorker.new(
        %{
          "snapshot_id" => snapshot.id,
          "user_id" => crawl_run.user_id,
          "link_id" => crawl_run.link_id,
          "url" => crawl_run.final_url || crawl_run.url,
          "type" => type,
          "recrawl" => Keyword.get(opts, :recrawl, false),
          "crawl_run_id" => crawl_run.id,
          "preflight_meta" => preflight_meta,
          "link_inserted_at" => encode_datetime(link_inserted_at)
        },
        queue: to_string(crawler_module.queue())
      )
    end)
    |> Ecto.Multi.run({:link_snapshot_job, idx}, fn _repo, changes ->
      snapshot = changes[{:snapshot, idx}]
      job = changes[{:job, idx}]
      Archiving.update_snapshot(snapshot, %{job_id: job.id})
    end)
  end

  defp encode_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_datetime(_), do: nil

  defp get_link_inserted_at(link_id) do
    case Repo.get_by(Link, id: link_id) do
      %Link{inserted_at: inserted_at} -> inserted_at
      nil -> nil
    end
  end
end
