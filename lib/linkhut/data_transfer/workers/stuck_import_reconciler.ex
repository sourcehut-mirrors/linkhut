defmodule Linkhut.DataTransfer.Workers.StuckImportReconciler do
  @moduledoc """
  Periodic worker that finalizes stuck imports (ie: import is still marked as active but its corresponding
  Oban job has terminated or no longer exists)
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: {1, :hour}, states: :incomplete]

  alias Linkhut.DataTransfer

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    stuck = DataTransfer.list_stuck_imports()

    Enum.each(stuck, &finalize/1)

    Logger.info("ImportReconciler: finalized #{length(stuck)} stuck import(s)")
    :ok
  end

  defp finalize(import) do
    DataTransfer.mark_failed(import, "Import was interrupted and did not finish.")
    if import.file, do: File.rm(import.file)
  end
end
