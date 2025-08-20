defmodule Linkhut.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :linkhut

  def run(args) do
    [task | args] = String.split(args)

    mix_task(task, args)
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp find_module(task) do
    module_name =
      task
      |> String.split(".")
      |> Enum.map(&String.capitalize/1)
      |> then(fn x -> [Mix, Tasks, Linkhut] ++ x end)
      |> Module.concat()

    case Code.ensure_loaded(module_name) do
      {:module, _} -> module_name
      _ -> nil
    end
  end

  defp mix_task(task, args) do
    load_app()

    module = find_module(task)

    if module do
      module.run(args)
    else
      IO.puts("The task #{task} does not exist")
    end
  end
end
