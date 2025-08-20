defmodule Mix.Tasks.Linkhut do
  use Mix.Task

  @shortdoc "Prints Linkhut help information"

  @moduledoc """
  Prints Linkhut tasks and their information.

      $ mix linkhut

  """

  @impl true
  def run(args) do
    {_opts, args} = OptionParser.parse!(args, strict: [])

    case args do
      [] -> general()
      _ -> Mix.raise("Invalid arguments, expected: mix linkhut")
    end
  end

  defp general() do
    Application.ensure_all_started(:ecto)
    Mix.shell().info("Linkhut v#{Mix.Project.config()[:version]}")
    Mix.shell().info("An open source social bookmarking website.")
    Mix.shell().info("\nAvailable tasks:\n")
    Mix.Tasks.Help.run(["--search", "linkhut."])
  end
end
