defmodule Linkhut.DataTransfer.Workers.Importer do
  @moduledoc """
  Oban worker that processes bookmark import files asynchronously.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Linkhut.Accounts
  alias Linkhut.DataTransfer

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: id,
        attempt: attempt,
        max_attempts: max,
        args: %{"user_id" => user_id, "file" => file, "overrides" => overrides}
      }) do
    user = Accounts.get_user!(user_id)
    import = DataTransfer.get_import(user_id, id)

    case File.read(file) do
      {:ok, document} ->
        try do
          result = process_document(import, user, document, overrides)
          File.rm(file)
          result
        rescue
          e ->
            if attempt >= max do
              DataTransfer.mark_failed(import, "Import failed after #{max} attempts.")
              File.rm(file)
            end

            reraise e, __STACKTRACE__
        end

      {:error, reason} ->
        DataTransfer.mark_failed(import, "Failed to read uploaded file: #{reason}")
        File.rm(file)
        {:cancel, reason}
    end
  end

  defp process_document(import, user, document, overrides) do
    case DataTransfer.parse(document) do
      {:error, :unsupported_format} ->
        DataTransfer.mark_failed(import, "Unsupported file format")
        {:cancel, :unsupported_format}

      {:ok, bookmarks} ->
        DataTransfer.import_bookmarks(import, user, bookmarks, overrides)
        :ok
    end
  end
end
