defmodule Linkhut.DataTransfer.Workers.ImportWorker do
  @moduledoc """
  Oban worker that processes bookmark import files asynchronously.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Linkhut.Accounts
  alias Linkhut.Accounts.Preferences
  alias Linkhut.DataTransfer
  alias Linkhut.Links

  @chunk_size 50

  @doc """
  Returns the PID of the Oban supervisor process.

  Used by the import controller to transfer uploaded file ownership
  via `Plug.Upload.give_away/2` so the file outlives the request.
  """
  def get_pid() do
    Oban.whereis(Oban)
  end

  def enqueue(user, file, overrides \\ %{}) do
    {:ok, job} =
      %{user_id: user.id, file: file, overrides: overrides}
      |> new()
      |> Oban.insert()

    DataTransfer.create_import(user, job, overrides)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: id,
        args: %{"user_id" => user_id, "file" => file, "overrides" => overrides}
      }) do
    user = Accounts.get_user!(user_id)

    try do
      case File.read(file) do
        {:ok, document} ->
          process_document(user, user_id, id, document, overrides)

        {:error, reason} ->
          import_record = DataTransfer.get_import(user_id, id)

          DataTransfer.update_import(import_record, %{
            state: :failed,
            invalid_entries: ["Failed to read uploaded file: #{reason}"]
          })

          {:error, reason}
      end
    after
      File.rm(file)
    end
  end

  defp process_document(user, user_id, job_id, document, overrides) do
    case DataTransfer.parse(document) do
      {:error, :unsupported_format} ->
        import_record = DataTransfer.get_import(user_id, job_id)

        DataTransfer.update_import(import_record, %{
          state: :failed,
          invalid_entries: ["Unsupported file format"]
        })

        {:error, :unsupported_format}

      {:ok, bookmarks} ->
        process_bookmarks(user, user_id, job_id, bookmarks, overrides)
    end
  end

  defp process_bookmarks(user, user_id, job_id, bookmarks, overrides) do
    import_record = DataTransfer.get_import(user_id, job_id)
    prefs = Preferences.get_or_default(user)
    total = length(bookmarks)

    {:ok, import_record} =
      DataTransfer.update_import(import_record, %{
        state: :in_progress,
        total: total,
        saved: 0,
        failed: 0,
        invalid: 0
      })

    acc = %{saved: 0, failed: 0, invalid: 0, failed_records: [], invalid_entries: []}

    {acc, import_record} =
      bookmarks
      |> Enum.chunk_every(@chunk_size)
      |> Enum.reduce({acc, import_record}, fn chunk, {acc, import_record} ->
        chunk_acc =
          Enum.reduce(chunk, acc, fn bookmark, acc ->
            bookmark = maybe_clean_bookmark(bookmark, prefs)
            result = DataTransfer.save_bookmark(user, bookmark, overrides)
            accumulate_result(acc, result)
          end)

        {:ok, import_record} =
          DataTransfer.update_import(import_record, %{
            saved: chunk_acc.saved,
            failed: chunk_acc.failed,
            invalid: chunk_acc.invalid
          })

        {chunk_acc, import_record}
      end)

    DataTransfer.update_import(import_record, %{
      state: :complete,
      total: total,
      saved: acc.saved,
      failed: acc.failed,
      invalid: acc.invalid,
      failed_records: acc.failed_records,
      invalid_entries: acc.invalid_entries
    })
  end

  defp maybe_clean_bookmark({:ok, attrs}, prefs) do
    {:ok, Links.maybe_clean_url(attrs, prefs)}
  end

  defp maybe_clean_bookmark(error, _prefs), do: error

  defp accumulate_result(acc, {:ok, _}) do
    Map.update!(acc, :saved, &(&1 + 1))
  end

  defp accumulate_result(acc, {:error, entry}) when is_binary(entry) do
    acc
    |> Map.update!(:invalid, &(&1 + 1))
    |> Map.update!(:invalid_entries, &[entry | &1])
  end

  defp accumulate_result(acc, {:error, %{changes: changes} = changeset}) do
    record =
      Map.put(
        changes,
        :errors,
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end)
      )

    acc
    |> Map.update!(:failed, &(&1 + 1))
    |> Map.update!(:failed_records, &[record | &1])
  end
end
