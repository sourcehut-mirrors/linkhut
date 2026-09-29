defmodule Linkhut.Archiving.Workers.StaleSnapshotSweeper do
  @moduledoc """
  Worker that marks snapshots as failed when they are stuck as `:pending` or
  `:crawling` for more than 30 minutes and when there's no active job working
  on them.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: {1, :minute}]

  import Ecto.Query

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{LinkArchival, Log, Snapshot}
  alias Linkhut.Repo

  require Logger

  @stale_threshold_minutes 30
  @live_job_states ["available", "executing", "scheduled", "retryable"]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_threshold_minutes, :minute)

    from(s in Snapshot,
      as: :snapshot,
      where: s.state in [:pending, :crawling] and s.updated_at < ^cutoff,
      where:
        not exists(
          from j in Oban.Job,
            where: j.id == parent_as(:snapshot).job_id and j.state in @live_job_states
        )
    )
    |> Repo.all()
    |> Enum.each(&mark_failed/1)
  end

  defp mark_failed(%Snapshot{} = snapshot) do
    Logger.warning("Marking stale snapshot #{snapshot.id} as failed (stuck in #{snapshot.state})")

    attrs = %{
      failed_at: DateTime.utc_now(),
      archive_metadata: %{
        error: "snapshot stuck in #{snapshot.state}, marked failed by sweeper",
        error_code: "stale"
      }
    }

    with {:ok, _snapshot} <- Archiving.mark_snapshot(snapshot, :failed, attrs) do
      run_id =
        Repo.one(
          from a in LinkArchival, where: a.snapshot_id == ^snapshot.id, select: a.crawl_run_id
        )

      snapshot
      |> Log.for_snapshot(run_id)
      |> Log.append("crawler.abandoned", %{previous_state: to_string(snapshot.state)},
        level: :error
      )
    end
  end
end
