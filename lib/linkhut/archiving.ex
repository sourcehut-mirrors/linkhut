defmodule Linkhut.Archiving do
  @moduledoc """
  Link archiving context. Handles creating snapshots of bookmarked pages and
  storing them.
  """

  import Ecto.Query

  alias Linkhut.Accounts
  alias Linkhut.Accounts.User
  alias Linkhut.Archiving.{CrawlRun, Format, Snapshot, Storage}
  alias Linkhut.Links.Link

  require Logger
  alias Linkhut.{Repo, Subscriptions}

  @doc """
  Returns the archiving mode.

  - `:disabled`: no archiving features
  - `:enabled`: archiving for all active users
  - `:limited`: archiving only for active paying users
  """
  def mode, do: Linkhut.Config.archiving(:mode, :disabled)

  @doc "Returns true if the user can create new archives."
  @spec can_create_archives?(User.t()) :: boolean()
  def can_create_archives?(%User{type: :active} = user) do
    case mode() do
      :disabled -> false
      :enabled -> true
      :limited -> Subscriptions.active_plan(user) == :supporter
    end
  end

  def can_create_archives?(_), do: false

  @doc """
  Returns true if the user can view/download existing archives.
  Any active user can view when archiving isn't disabled.
  """
  @spec can_view_archives?(User.t()) :: boolean()
  def can_view_archives?(%User{type: :active}) do
    mode() != :disabled
  end

  def can_view_archives?(_), do: false

  @doc """
  Returns the list of users eligible for archiving based on the current mode.

  - `:disabled` → empty list
  - `:limited` → users with an active supporter subscription
  - `:enabled` → all active users
  """
  def eligible_users do
    case mode() do
      :disabled -> []
      :limited -> Subscriptions.list_subscribed_users([:supporter])
      :enabled -> Accounts.list_active_users()
    end
  end

  @doc "Enqueues a re-crawl of `link`."
  def enqueue_recrawl(link, opts \\ []) do
    Linkhut.Archiving.Workers.Archiver.enqueue(link, [recrawl: true] ++ opts)
  end

  # --- Snapshot functions ---

  @doc "Returns a complete snapshot by ID, or `{:error, :not_found}`."
  def get_complete_snapshot(id) do
    case Repo.get(Snapshot, id) do
      %Snapshot{state: :complete} = snapshot -> {:ok, snapshot}
      _ -> {:error, :not_found}
    end
  end

  @doc "Returns all complete snapshots for a link."
  def get_complete_snapshots_by_link(link_id) do
    Snapshot
    |> where(link_id: ^link_id, state: :complete)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc "Returns all non-deleted snapshots for a link, ordered by format locality then recency."
  def get_current_snapshots_by_link(link_id) do
    Snapshot
    |> where([s], s.link_id == ^link_id and s.state != :pending_deletion)
    |> order_by([s], asc: s.format, desc: s.inserted_at)
    |> Repo.all()
    |> Enum.sort_by(&Format.format_sort_key(&1.format))
  end

  @doc """
  Returns the latest complete snapshot of a link in `format`, for a given
  `source` (when given).
  """
  def get_latest_complete_snapshot(link_id, format, source) do
    Snapshot
    |> where(link_id: ^link_id, format: ^format, state: :complete)
    |> then(&if(source, do: where(&1, source: ^source), else: &1))
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      snapshot -> {:ok, snapshot}
    end
  end

  @doc "Returns all crawl runs for a link."
  def get_crawl_runs_by_link(link_id) do
    from(cr in CrawlRun,
      where: cr.link_id == ^link_id,
      order_by: [desc: cr.inserted_at, desc: cr.id],
      preload: :events
    )
    |> Repo.all()
  end

  @live_job_states ["available", "scheduled", "executing", "retryable"]

  @doc """
  Returns true while an Archiver job for `link` is live or one of its
  snapshots is pending or crawling.
  """
  @spec archiving?(Link.t()) :: boolean()
  def archiving?(%Link{id: link_id}) do
    Repo.exists?(
      from(j in Oban.Job,
        where: j.worker == ^inspect(Linkhut.Archiving.Workers.Archiver),
        where: j.state in @live_job_states,
        where: fragment("? @> ?", j.args, type(^%{link_id: link_id}, :map))
      )
    ) or
      Repo.exists?(
        from(s in Snapshot, where: s.link_id == ^link_id and s.state in [:pending, :crawling])
      )
  end

  @doc "Gets a snapshot by its ID."
  def get_snapshot_by_id(id) do
    Repo.get(Snapshot, id)
  end

  @doc """
  Uploads a user-provided snapshot for a link.

  Detects the format from the content type and supersedes older snapshots of
  the same format (meaning that uploads always trump prior uploads and any
  snapshots produced by crawlers).
  """
  def upload_snapshot(link_id, user_id, %Plug.Upload{} = upload) do
    with {:ok, content_type} <- Linkhut.Archiving.MIME.detect(upload.path),
         {:ok, format} <- detect_upload_format(content_type),
         {:ok, snapshot} <-
           Repo.transact(fn -> insert_upload(link_id, user_id, format, content_type, upload) end) do
      supersede(snapshot)
      {:ok, snapshot}
    end
  end

  defp insert_upload(link_id, user_id, format, content_type, upload) do
    with {:ok, snapshot} <- create_upload_snapshot(link_id, user_id, format),
         {:ok, stored} <- store_file(snapshot, upload.path, content_type) do
      metadata = %{content_type: content_type, original_filename: upload.filename}
      update_snapshot(snapshot, Map.put(stored, :archive_metadata, metadata))
    end
  end

  @doc """
  Stores the file at `path` as `snapshot`'s content, if and only if it is
  within `max_file_size`.
  """
  @spec store_file(Snapshot.t(), Path.t(), String.t()) ::
          {:ok, map()}
          | {:error, {:file_too_large, non_neg_integer(), non_neg_integer()}}
          | {:error, term()}
  def store_file(%Snapshot{} = snapshot, path, content_type) do
    max = Linkhut.Config.archiving(:max_file_size)

    with {:ok, %{size: size}} <- File.stat(path),
         :ok <- if(size > max, do: {:error, {:file_too_large, size, max}}, else: :ok),
         {:ok, key, meta} <- Storage.store({:file, path}, snapshot, content_type: content_type) do
      {:ok,
       %{
         storage_key: key,
         file_size_bytes: meta.file_size_bytes,
         encoding: meta.encoding,
         original_file_size_bytes: if(meta.encoding, do: size)
       }}
    end
  end

  @doc "Returns the list of content types accepted for snapshot uploads."
  def accepted_upload_types, do: Linkhut.Archiving.MIME.types()

  defp detect_upload_format(content_type) do
    case Linkhut.Archiving.MIME.format(content_type) do
      nil -> {:error, :unsupported_format}
      format -> {:ok, format}
    end
  end

  defp create_upload_snapshot(link_id, user_id, format) do
    %{
      link_id: link_id,
      user_id: user_id,
      format: format,
      source: "upload",
      state: :complete
    }
    |> Snapshot.upload_changeset()
    |> Repo.insert()
  end

  @doc "Updates a snapshot's attributes."
  def update_snapshot(%Snapshot{} = snapshot, attrs) do
    snapshot
    |> Snapshot.update_changeset(attrs)
    |> Repo.update()
  end

  @active_states [:pending, :crawling]

  @doc "Marks a single snapshot as pending deletion."
  def request_snapshot_deletion(snapshot_id, user_id) do
    case Repo.get_by(Snapshot, id: snapshot_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      %Snapshot{state: state} when state in @active_states ->
        {:error, :active}

      %Snapshot{state: :pending_deletion} = snapshot ->
        {:ok, snapshot}

      snapshot ->
        update_snapshot(snapshot, %{state: :pending_deletion})
    end
  end

  @doc "Marks all snapshots for a link as pending deletion."
  def mark_snapshots_for_deletion(link_id) do
    from(s in Snapshot, where: s.link_id == ^link_id and s.state != :pending_deletion)
    |> Repo.update_all(set: [state: :pending_deletion])

    :ok
  end

  @doc """
  Enqueues a `SnapshotDeleter` job for each snapshot in `pending_deletion` state.
  """
  def enqueue_pending_deletions do
    snapshot_ids =
      Snapshot
      |> where(state: :pending_deletion)
      |> select([s], s.id)
      |> Repo.all()

    snapshot_ids
    |> Enum.map(&Linkhut.Archiving.Workers.SnapshotDeleter.new(%{"snapshot_id" => &1}))
    |> Oban.insert_all()

    :ok
  end

  @doc """
  Deletes a single snapshot's storage and database record.
  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  def delete_snapshot(snapshot_id) when is_integer(snapshot_id) do
    case Repo.get(Snapshot, snapshot_id) do
      %Snapshot{state: :pending_deletion} = snapshot ->
        do_delete_snapshot(snapshot)

      _ ->
        :ok
    end
  end

  defp do_delete_snapshot(snapshot) do
    with :ok <- delete_snapshot_storage(snapshot),
         {:ok, _} <- Repo.delete(snapshot) do
      :ok
    end
  end

  defp delete_snapshot_storage(%Snapshot{storage_key: nil}), do: :ok
  defp delete_snapshot_storage(%Snapshot{storage_key: key}), do: Storage.delete(key)

  @doc """
  Records that a crawler's snapshot reached a terminal state.

  If the state of this snapshot is as good or better than the state of a prior
  snapshot for the same link and format, then it marks those older snapshots
  for deletion:

    - `:complete` trumps `:complete`, `:not_available` and `:failed`
    - `:not_available` trumps `:not_available` and `:failed`
    - `:failed` trumps `:failed`

  Note: A crawler's snapshot never replaces an upload.
  """
  @spec mark_snapshot(Snapshot.t(), :complete | :not_available | :failed, map()) ::
          {:ok, Snapshot.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def mark_snapshot(%Snapshot{} = snapshot, state, attrs)
      when state in [:complete, :not_available, :failed] do
    Repo.transact(fn ->
      case Repo.one(from(s in Snapshot, where: s.id == ^snapshot.id, lock: "FOR UPDATE")) do
        nil ->
          {:error, :not_found}

        %Snapshot{state: :pending_deletion} = current ->
          update_snapshot(current, attrs)

        current ->
          with {:ok, updated} <- update_snapshot(current, Map.put(attrs, :state, state)) do
            supersede(updated)
            {:ok, updated}
          end
      end
    end)
    |> case do
      {:error, %Ecto.Changeset{} = changeset} = error ->
        Logger.warning(
          "Failed to mark snapshot #{snapshot.id} as #{state}: #{inspect(changeset.errors)}"
        )

        error

      result ->
        result
    end
  end

  defp supersede(%Snapshot{} = snapshot) do
    from(s in Snapshot,
      where: s.link_id == ^snapshot.link_id and s.format == ^snapshot.format,
      where: s.state in ^superseded_states(snapshot.state) and s.id != ^snapshot.id,
      where: ^(snapshot.source == "upload") or s.source != "upload"
    )
    |> Repo.update_all(set: [state: :pending_deletion])
  end

  defp superseded_states(:complete), do: [:complete, :not_available, :failed]
  defp superseded_states(:not_available), do: [:not_available, :failed]
  defp superseded_states(:failed), do: [:failed]
end
