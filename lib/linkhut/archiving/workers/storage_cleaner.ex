defmodule Linkhut.Archiving.Workers.StorageCleaner do
  @moduledoc """
  Fan-out worker that finds snapshots in `pending_deletion` state and
  enqueues a `SnapshotDeleter` job for each one.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: {1, :minute}]

  alias Linkhut.Archiving

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Archiving.enqueue_pending_deletions()
  end
end
