defmodule Linkhut.Archiving.Workers.SnapshotDeleter do
  @moduledoc """
  Deletes a single snapshot's storage and database record.

  Enqueued by `StorageCleaner` for each snapshot in `pending_deletion` state.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5

  alias Linkhut.Archiving

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"snapshot_id" => snapshot_id}}) do
    Archiving.delete_snapshot(snapshot_id)
  end
end
