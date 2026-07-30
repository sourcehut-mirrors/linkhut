defmodule Linkhut.DataTransfer do
  @moduledoc """
  Module for importing and exporting links.
  """

  import Ecto.Query

  alias Linkhut.Accounts.Preferences
  alias Linkhut.Accounts.User
  alias Linkhut.Config
  alias Linkhut.DataTransfer.Import
  alias Linkhut.DataTransfer.Parser
  alias Linkhut.DataTransfer.Parsers
  alias Linkhut.DataTransfer.Workers.Importer
  alias Linkhut.Links
  alias Linkhut.Links.Link
  alias Linkhut.Repo

  require Logger

  @parsers [Parsers.Netscape]

  @spec parse(String.t()) :: {:ok, [Parser.bookmark()]} | {:error, :unsupported_format}
  def parse(document) do
    case detect_parser(document) do
      {:ok, parser} -> parser.parse_document(document)
      :error -> {:error, :unsupported_format}
    end
  end

  defp detect_parser(document) do
    case Enum.find(@parsers, & &1.can_parse?(document)) do
      nil -> :error
      parser -> {:ok, parser}
    end
  end

  @spec export(User.t()) :: [Linkhut.Links.Link.t()]
  def export(user) do
    Links.all(user)
  end

  @doc """
  Streams a user's links inside a transaction, passing the stream to the
  given callback. This avoids loading all links into memory at once.
  """
  @spec export_stream(User.t(), (Enumerable.t() -> result)) :: result when result: var
  def export_stream(user, callback) do
    query =
      from(l in Link,
        where: l.user_id == ^user.id,
        order_by: [desc: l.inserted_at]
      )

    Repo.transaction(fn ->
      query
      |> Repo.stream()
      |> callback.()
    end)
    |> elem(1)
  end

  @doc "Schedules an asynchronous task to import bookmarks from the uploaded file"
  @spec create_import(User.t(), String.t(), map()) ::
          {:ok, Import.t()} | {:error, Ecto.Changeset.t()}
  def create_import(user, upload, overrides) do
    file =
      Path.join([
        Config.data_transfer(:upload_dir),
        user.username,
        "#{DateTime.utc_now() |> DateTime.to_unix(:millisecond)}"
      ])

    File.mkdir_p!(Path.dirname(file))
    File.cp!(upload, file)

    result =
      Ecto.Multi.new()
      |> Oban.insert(
        :job,
        Importer.new(%{user_id: user.id, file: file, overrides: overrides})
      )
      |> Ecto.Multi.insert(:import, fn %{job: job} ->
        Import.changeset(
          %Import{user_id: user.id, job_id: job.id, file: file, overrides: overrides},
          %{}
        )
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{import: import}} ->
        {:ok, import}

      {:error, _step, reason, _changes} ->
        File.rm(file)
        {:error, reason}
    end
  end

  @doc "Imports given bookmarks"
  @spec import_bookmarks(Import.t(), User.t(), [Parser.bookmark()], map()) :: :ok
  def import_bookmarks(%Import{} = import, user, bookmarks, overrides) do
    mark_in_progress(import, length(bookmarks))
    preferences = Preferences.get_or_default(user)

    bookmarks
    |> Enum.drop(Import.processed_count(import))
    |> Enum.each(&import_bookmark(import, user, &1, overrides, preferences))

    mark_complete(import)
  end

  @doc "Marks import as failed with the given message"
  @spec mark_failed(Import.t(), String.t()) :: :ok
  def mark_failed(import, message) do
    update_import(import, %{state: :failed, invalid_entries: [message]})
    :ok
  rescue
    e ->
      Logger.error("Could not mark import #{import.id} as failed: #{Exception.message(e)}")
      :ok
  end

  @spec get_import(integer(), integer()) :: Import.t() | nil
  def get_import(user_id, job_id) do
    Import
    |> Repo.get_by(user_id: user_id, job_id: job_id)
  end

  @spec has_active_import?(integer()) :: boolean()
  def has_active_import?(user_id) do
    Import
    |> where(user_id: ^user_id)
    |> where([i], i.state in [:queued, :in_progress])
    |> Repo.exists?()
  end

  @doc """
  Returns imports that are stuck: still marked active but whose Oban job
  has terminated or been pruned, and which haven't been touched recently.
  """
  @spec list_stuck_imports() :: [Import.t()]
  def list_stuck_imports() do
    # 15 minutes cutoff to avoid racing with an active import
    cutoff = DateTime.add(DateTime.utc_now(), -15, :minute)

    from(i in Import,
      left_join: j in Oban.Job,
      on: j.id == i.job_id,
      where: i.state in [:queued, :in_progress],
      where: i.updated_at < ^cutoff,
      where: is_nil(j.id) or j.state in ["completed", "discarded", "cancelled"]
    )
    |> Repo.all()
  end

  defp mark_in_progress(import, total),
    do: update_import(import, %{state: :in_progress, total: total})

  defp mark_complete(import), do: update_import(import, %{state: :complete})

  defp update_import(%Import{} = import, attrs) do
    import
    |> Import.changeset(attrs)
    |> Repo.update()
  end

  defp import_bookmark(%Import{} = import, user, bookmark, overrides, preferences) do
    Repo.transact(fn ->
      case save_bookmark(user, bookmark, overrides, preferences) do
        :saved ->
          record_saved(import)
          {:ok, :saved}

        outcome ->
          {:error, outcome}
      end
    end)
    |> handle_outcome(import)
  end

  defp handle_outcome({:ok, :saved}, _import), do: :saved

  defp handle_outcome({:error, {:invalid, msg} = outcome}, import) do
    record_invalid(import, msg)
    outcome
  end

  defp handle_outcome({:error, {:failed, changeset} = outcome}, import) do
    record_failed(import, changeset)
    outcome
  end

  defp record_saved(import) do
    from(i in Import, where: i.id == ^import.id)
    |> Repo.update_all(inc: [saved: 1])
  end

  defp record_invalid(import, msg) do
    from(i in Import, where: i.id == ^import.id)
    |> Repo.update_all(inc: [invalid: 1], push: [invalid_entries: msg])
  end

  defp record_failed(import, changeset) do
    Repo.transact(fn ->
      # reload import under lock to ensure counters and records aren't stale before updating
      import = Repo.get(Import |> lock("FOR UPDATE"), import.id)

      import
      |> Import.changeset(%{
        failed: import.failed + 1,
        failed_records: [
          build_record(changeset) | Enum.map(import.failed_records, &Map.from_struct/1)
        ]
      })
      |> Repo.update()
    end)
  end

  defp build_record(%{changes: changes} = changeset) do
    Map.put(
      changes,
      :errors,
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)
    )
  end

  defp save_bookmark(user, {:ok, attrs}, %{"is_private" => "true"} = overrides, preferences) do
    attrs = Map.replace(attrs, :is_private, true)
    overrides = Map.drop(overrides, ["is_private"])

    save_bookmark(user, {:ok, attrs}, overrides, preferences)
  end

  defp save_bookmark(user, {:ok, attrs}, _overrides, preferences) do
    attrs = Links.maybe_clean_url(attrs, preferences)

    case Links.create_link(user, attrs) do
      {:ok, _} -> :saved
      {:error, changeset} -> {:failed, changeset}
    end
  end

  defp save_bookmark(_user, {:error, msg}, _overrides, _preferences) do
    {:invalid, msg}
  end
end
