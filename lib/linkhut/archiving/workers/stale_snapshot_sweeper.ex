defmodule Linkhut.Archiving.Workers.StaleSnapshotSweeper do
  @moduledoc """
  Periodic worker that finds snapshots stuck in non-terminal states
  (`:crawling`, `:retryable`) for longer than the configured threshold
  and marks them as `:failed`.

  This covers edge cases where the Crawler worker process is killed
  (node crash, `kill -9`, OOM) before it can update the snapshot state.
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

    :ok
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
        Archiving.maybe_complete_archive(snapshot.archive_id)

      {:error, changeset} ->
        Logger.warning(
          "Failed to mark stale snapshot #{snapshot.id} as failed: #{inspect(changeset.errors)}"
        )
    end
  end
end
