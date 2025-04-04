defmodule Linkhut.Workers.ImportWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Linkhut.Dump
  alias Linkhut.Accounts
  alias Linkhut.Jobs

  def get_pid() do
    Oban.whereis(Oban)
  end

  def enqueue(user, file, overrides \\ %{}) do
    {:ok, job} =
      %{user_id: user.id, file: file, overrides: overrides}
      |> Linkhut.Workers.ImportWorker.new()
      |> Oban.insert()

    Jobs.create_import(user, job, overrides)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: id,
        args: %{"user_id" => user_id, "file" => file, "overrides" => overrides}
      }) do
    user = Accounts.get_user!(user_id)
    result = Dump.import(user, File.read!(file), overrides)
    File.rm(file)

    job = Jobs.get_import(user_id, id)

    case Jobs.update_import(job, %{
           state: :complete,
           total: Enum.count(result),
           saved:
             Enum.count(result, fn x ->
               case x,
                 do: (
                   {:ok, _} -> true
                   _ -> false
                 )
             end),
           failed:
             Enum.count(result, fn x ->
               case x,
                 do: (
                   {:ok, _} -> false
                   {:error, entry} when is_binary(entry) -> false
                   _ -> true
                 )
             end),
           invalid:
             Enum.count(result, fn x ->
               case x,
                 do: (
                   {:error, entry} when is_binary(entry) -> true
                   _ -> false
                 )
             end),
           failed_records:
             Enum.flat_map(result, fn x ->
               case x do
                 {:ok, _} ->
                   []

                 {:error, %{changes: changes} = changeset} ->
                   [
                     Map.put(
                       changes,
                       :errors,
                       Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
                         Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
                           opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
                         end)
                       end)
                     )
                   ]

                 {:error, _} ->
                   []
               end
             end),
           invalid_entries:
             Enum.flat_map(result, fn x ->
               case x do
                 {:error, entry} when is_binary(entry) ->
                   [entry]

                 {_, _} ->
                   []
               end
             end)
         }) do
      {:ok, _} -> {:ok, result}
      {:error, changeset} -> {:error, changeset}
    end
  end
end
