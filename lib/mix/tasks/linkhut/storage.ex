defmodule Mix.Tasks.Linkhut.Storage do
  use Mix.Task

  import Mix.Linkhut

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Storage

  @moduledoc """
  Shows and manages archiving storage statistics.

  ## Usage

      mix linkhut.storage              # Show storage stats
      mix linkhut.storage recompute    # Recompute all archive sizes, then show stats
  """

  @shortdoc "Shows archiving storage statistics"

  def run(["recompute"]) do
    start_linkhut()

    shell_info("Recomputing all archive sizes...")
    Archiving.recompute_all_archive_sizes()
    shell_info("Done.")

    show_stats()
  end

  def run([]) do
    start_linkhut()
    show_stats()
  end

  def run(_), do: shell_error("Usage: mix linkhut.storage [recompute]")

  defp show_stats do
    db_bytes = Archiving.storage_used()
    {:ok, disk_bytes} = Storage.storage_used()

    shell_info("Storage (DB total):   #{Linkhut.Formatting.format_bytes(db_bytes)}")
    shell_info("Storage (disk total): #{Linkhut.Formatting.format_bytes(disk_bytes)}")
  end
end
