defmodule Mix.Tasks.Linkhut.Storage do
  use Mix.Task

  import Mix.Linkhut

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Storage

  @moduledoc """
  Shows archiving storage statistics.

  ## Usage

      mix linkhut.storage              # Show storage stats
  """

  @shortdoc "Shows archiving storage statistics"

  def run([]) do
    start_linkhut()
    show_stats()
  end

  def run(_), do: shell_error("Usage: mix linkhut.storage")

  defp show_stats do
    db_bytes = Archiving.storage_used()
    {:ok, disk_bytes} = Storage.storage_used()

    shell_info("Storage (DB total):   #{Linkhut.Formatting.format_bytes(db_bytes)}")
    shell_info("Storage (disk total): #{Linkhut.Formatting.format_bytes(disk_bytes)}")
  end
end
