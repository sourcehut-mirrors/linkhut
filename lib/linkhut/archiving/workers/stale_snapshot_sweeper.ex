defmodule Linkhut.Archiving.Workers.StaleSnapshotSweeper do
  @moduledoc """
  Periodic worker that finds snapshots stuck in non-terminal states
  and marks them as `:failed`.

  Two sweep passes:

  1. **Stale threshold** — snapshots in `:crawling` or `:retryable` for
     longer than `@stale_threshold_minutes` without an active Oban job.
     Covers node crashes, OOM kills, etc.

  2. **Discarded/cancelled jobs** — snapshots in any non-terminal state
     (`:pending`, `:crawling`, `:retryable`) whose Oban job has been
     discarded or cancelled. Covers jobs that exhausted all attempts
     without the crawler updating the snapshot.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: {1, :minute}]

  import Ecto.Query

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Snapshot, Steps}
  alias Linkhut.Archiving.Workers.Crawler
  alias Linkhut.Repo

  require Logger

  @stale_threshold_minutes 30
  @crawler_worker inspect(Crawler)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    sweep_stale_snapshots()
    sweep_discarded_jobs()
    :ok
  end

  defp sweep_stale_snapshots do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_threshold_minutes, :minute)

    stale_snapshots =
      Snapshot
      |> where([s], s.state in [:crawling, :retryable])
      |> where([s], s.updated_at < ^cutoff)
      |> Repo.all()

    active_snapshot_ids =
      from(j in Oban.Job,
        where: j.worker == @crawler_worker,
        where: j.state in ["available", "executing", "scheduled", "retryable"],
        select: fragment("(?->>'snapshot_id')::bigint", j.args)
      )
      |> Repo.all()
      |> MapSet.new()

    stale_snapshots
    |> Enum.reject(fn s -> s.id in active_snapshot_ids end)
    |> Enum.each(&mark_failed/1)
  end

  defp sweep_discarded_jobs do
    discarded_snapshot_ids =
      from(j in Oban.Job,
        where: j.worker == @crawler_worker,
        where: j.state in ["discarded", "cancelled"],
        select: fragment("(?->>'snapshot_id')::bigint", j.args)
      )
      |> Repo.all()
      |> MapSet.new()

    if MapSet.size(discarded_snapshot_ids) > 0 do
      Snapshot
      |> where([s], s.id in ^MapSet.to_list(discarded_snapshot_ids))
      |> where([s], s.state in [:pending, :crawling, :retryable])
      |> Repo.all()
      |> Enum.each(&mark_failed/1)
    end
  end

  defp mark_failed(%Snapshot{} = snapshot) do
    Logger.warning("Marking stale snapshot #{snapshot.id} as failed (stuck in #{snapshot.state})")

    case Archiving.update_snapshot(snapshot, %{
           state: :failed,
           failed_at: DateTime.utc_now(),
           crawl_info:
             Steps.add_crawl_step(snapshot.crawl_info, "failed", %{
               "msg" => "stale_snapshot_swept",
               "previous_state" => to_string(snapshot.state)
             }),
           archive_metadata: %{
             error: "snapshot stuck in #{snapshot.state}, marked failed by sweeper"
           }
         }) do
      {:ok, _} ->
        Archiving.maybe_complete_crawl_run(snapshot.crawl_run_id)

      {:error, changeset} ->
        Logger.warning(
          "Failed to mark stale snapshot #{snapshot.id} as failed: #{inspect(changeset.errors)}"
        )
    end
  end
end
