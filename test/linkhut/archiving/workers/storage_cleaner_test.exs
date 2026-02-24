defmodule Linkhut.Archiving.Workers.StorageCleanerTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Workers.StorageCleaner

  test "perform/1 enqueues SnapshotDeleter jobs for pending_deletion snapshots" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, nil, %{state: :pending_deletion})

    assert :ok = perform_job(StorageCleaner, %{})

    assert_enqueued(
      worker: Linkhut.Archiving.Workers.SnapshotDeleter,
      args: %{"snapshot_id" => snapshot.id}
    )
  end

  test "perform/1 does not enqueue jobs when no pending_deletion snapshots exist" do
    assert :ok = perform_job(StorageCleaner, %{})

    refute_enqueued(worker: Linkhut.Archiving.Workers.SnapshotDeleter)
  end
end
