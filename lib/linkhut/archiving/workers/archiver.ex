defmodule Linkhut.Archiving.Workers.Archiver do
  @moduledoc """
  Validates a link's URL (SSRF checks, redirect following) and dispatches
  per-crawler jobs via `Linkhut.Archiving.Workers.Crawler`.

  This worker is intentionally thin — orchestration logic lives in
  `Linkhut.Archiving.Pipeline` for unit-testability.
  """

  use Oban.Worker,
    queue: :archiver,
    # Initial attempt + 3 retries
    max_attempts: 4,
    unique: [
      period: {1, :hour},
      keys: [:link_id, :recrawl],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Pipeline
  alias Linkhut.Repo

  require Logger

  def enqueue(link, opts \\ []) do
    recrawl = Keyword.get(opts, :recrawl, false)
    oban_opts = Keyword.drop(opts, [:recrawl])

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:crawl_run, fn _repo, _changes ->
        Archiving.create_crawl_run(%{
          link_id: link.id,
          user_id: link.user_id,
          url: link.url,
          state: :pending
        })
      end)
      |> Oban.insert(:job, fn %{crawl_run: crawl_run} ->
        args =
          %{user_id: link.user_id, link_id: link.id, url: link.url, crawl_run_id: crawl_run.id}
          |> maybe_add_recrawl(recrawl)

        __MODULE__.new(args, oban_opts)
      end)

    case Repo.transaction(multi) do
      {:ok, %{job: %{conflict?: true} = job, crawl_run: crawl_run}} ->
        # Job was a duplicate — clean up the orphaned crawl run
        case Repo.delete(crawl_run) do
          {:ok, _} ->
            :ok

          {:error, changeset} ->
            Logger.warning(
              "Failed to clean up orphaned crawl run #{crawl_run.id}: #{inspect(changeset.errors)}"
            )
        end

        {:ok, job}

      {:ok, %{job: job}} ->
        {:ok, job}

      {:error, :crawl_run, changeset, _} ->
        {:error, changeset}

      {:error, :job, changeset, _} ->
        {:error, changeset}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    %{"crawl_run_id" => crawl_run_id} = args
    recrawl = Map.get(args, "recrawl", false)

    case Archiving.start_processing(crawl_run_id) do
      {:ok, crawl_run} ->
        Pipeline.run(crawl_run,
          recrawl: recrawl,
          attempt: job.attempt,
          max_attempts: job.max_attempts
        )

      {:error, :not_found} ->
        :ok
    end
  end

  defp maybe_add_recrawl(args, recrawl) do
    if recrawl do
      Map.put(args, :recrawl, true)
    else
      args
    end
  end
end
