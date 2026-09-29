defmodule Linkhut.Archiving.Workers.StaleSnapshotSweeperTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving.Snapshot
  alias Linkhut.Archiving.Workers.StaleSnapshotSweeper

  defp stuck_snapshot(state, minutes) do
    ago = DateTime.utc_now() |> DateTime.add(-minutes, :minute) |> DateTime.truncate(:second)
    insert(:snapshot, state: state, updated_at: ago)
  end

  test "does not mark recent snapshots as failed" do
    snapshot = stuck_snapshot(:crawling, 5)

    assert :ok = perform_job(StaleSnapshotSweeper, %{})

    updated = Repo.get(Snapshot, snapshot.id)
    assert updated.state == :crawling
  end

  test "does not mark snapshots that have active Oban crawler jobs" do
    snapshot = stuck_snapshot(:crawling, 45)

    # Insert an active Oban job for this snapshot
    job =
      %{"snapshot_id" => snapshot.id}
      |> Linkhut.Archiving.Workers.Crawler.new()
      |> Oban.insert!()

    Repo.update_all(from(s in Snapshot, where: s.id == ^snapshot.id), set: [job_id: job.id])

    assert :ok = perform_job(StaleSnapshotSweeper, %{})

    updated = Repo.get(Snapshot, snapshot.id)
    assert updated.state == :crawling
  end

  test "marks a stale snapshot as :failed when its job is no longer live" do
    for {state, job_state} <- [
          pending: "discarded",
          crawling: "cancelled",
          pending: nil,
          crawling: nil
        ] do
      snapshot = stuck_snapshot(state, 45)

      if job_state do
        job =
          %{"snapshot_id" => snapshot.id}
          |> Linkhut.Archiving.Workers.Crawler.new()
          |> Oban.insert!()

        Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: job_state])
        Repo.update_all(from(s in Snapshot, where: s.id == ^snapshot.id), set: [job_id: job.id])
      end

      assert :ok = perform_job(StaleSnapshotSweeper, %{})

      assert Repo.get(Snapshot, snapshot.id).state == :failed,
             "for #{state} with #{job_state || "no"} job"
    end
  end

  test "does not touch :complete or :failed snapshots" do
    complete_snapshot = stuck_snapshot(:complete, 45)
    failed_snapshot = stuck_snapshot(:failed, 45)

    assert :ok = perform_job(StaleSnapshotSweeper, %{})

    assert Repo.get(Snapshot, complete_snapshot.id).state == :complete
    assert Repo.get(Snapshot, failed_snapshot.id).state == :failed
  end
end
