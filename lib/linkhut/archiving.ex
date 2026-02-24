defmodule Linkhut.Archiving do
  @moduledoc """
  Manages link archiving — creating snapshots of bookmarked pages,
  storing them, and generating time-limited tokens to view them.

  Crawling is handled by `Linkhut.Archiving.Workers.Archiver` and
  `Linkhut.Archiving.Workers.Crawler`, which call back into this context
  to persist results.
  """

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.Archiving.{Archive, Snapshot, Storage, Tokens}
  alias Linkhut.Links.Link
  alias Linkhut.Repo

  @doc """
  Returns the archiving mode.

  - `:disabled` — no archiving features
  - `:enabled` — archiving for all active users
  - `:limited` — archiving only for active paying users
  """
  def mode, do: Linkhut.Config.archiving(:mode, :disabled)

  @doc "Returns true if archiving features are available for the given user."
  def enabled_for_user?(%User{type: :active_paying}), do: mode() in [:enabled, :limited]
  def enabled_for_user?(%User{type: :active_free}), do: mode() == :enabled
  def enabled_for_user?(_), do: false

  @doc "Generates a short-lived token for serving a snapshot."
  def generate_token(snapshot_id), do: Tokens.generate_token(snapshot_id)

  @doc "Verifies a snapshot serving token, returning the snapshot_id or an error."
  def verify_token(token), do: Tokens.verify_token(token)

  # --- Archive functions ---

  @doc """
  Finds or creates an Archive by Oban job_id (idempotent).
  If an archive with the given job_id already exists, returns it.
  Otherwise creates a new one.
  """
  def get_or_create_archive(job_id, link_id, user_id, url) do
    case Repo.get_by(Archive, job_id: job_id) do
      %Archive{} = archive ->
        {:ok, archive}

      nil ->
        %Archive{}
        |> Archive.changeset(%{
          job_id: job_id,
          link_id: link_id,
          user_id: user_id,
          url: url,
          steps: []
        })
        |> Repo.insert()
        |> case do
          {:ok, archive} ->
            {:ok, archive}

          {:error, %Ecto.Changeset{errors: [{:job_id, _} | _]}} ->
            {:ok, Repo.get_by!(Archive, job_id: job_id)}

          {:error, _} = error ->
            error
        end
    end
  end

  @doc "Updates an archive's attributes."
  def update_archive(%Archive{} = archive, attrs) do
    archive
    |> Archive.changeset(attrs)
    |> Repo.update()
  end


  @doc """
  Marks old archives (and their snapshots) for deletion for a given link,
  excluding specific archive IDs.
  """
  def mark_old_archives_for_deletion(link_id, opts \\ []) do
    exclude_ids = Keyword.get(opts, :exclude, []) |> Enum.reject(&is_nil/1)

    archive_query =
      from(a in Archive,
        where: a.link_id == ^link_id and a.state == :active
      )

    archive_query =
      if exclude_ids != [] do
        from(a in archive_query, where: a.id not in ^exclude_ids)
      else
        archive_query
      end

    archive_ids = Repo.all(from(a in archive_query, select: a.id))

    if archive_ids != [] do
      from(a in Archive, where: a.id in ^archive_ids)
      |> Repo.update_all(set: [state: :pending_deletion])

      from(s in Snapshot, where: s.archive_id in ^archive_ids)
      |> Repo.update_all(set: [state: :pending_deletion])
    end

    :ok
  end

  @doc """
  Schedules a re-crawl for a link by enqueueing a new Archiver job
  with the recrawl flag.
  """
  def schedule_recrawl(link) do
    Linkhut.Archiving.Workers.Archiver.enqueue(link, recrawl: true)
  end

  # --- Snapshot functions ---

  @doc "Returns a complete snapshot by ID, or `{:error, :not_found}`."
  def get_complete_snapshot(id) do
    case Repo.get(Snapshot, id) do
      %Snapshot{state: :complete} = snapshot -> {:ok, snapshot}
      _ -> {:error, :not_found}
    end
  end

  @doc "Returns all complete snapshots for a link, newest first, with archive preloaded."
  def get_complete_snapshots_by_link(link_id) do
    Snapshot
    |> where(link_id: ^link_id, state: :complete)
    |> order_by([s], desc: s.inserted_at)
    |> preload(:archive)
    |> Repo.all()
  end

  @doc "Returns the latest complete snapshot of a given type for a link."
  def get_latest_complete_snapshot(link_id, type) do
    case Snapshot
         |> where(link_id: ^link_id, type: ^type, state: :complete)
         |> order_by([s], desc: s.inserted_at)
         |> limit(1)
         |> Repo.one() do
      nil -> {:error, :not_found}
      snapshot -> {:ok, snapshot}
    end
  end

  @doc "Returns all snapshots for a link (any state), newest first."
  def get_all_snapshots_by_link(link_id) do
    Snapshot
    |> where(link_id: ^link_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns all archives for a link (excluding pending_deletion),
  with preloaded snapshots (also excluding pending_deletion), newest first.
  """
  def get_archives_by_link(link_id) do
    from(a in Archive,
      where: a.link_id == ^link_id and a.state != :pending_deletion,
      order_by: [desc: a.inserted_at],
      preload: [
        snapshots:
          ^from(s in Snapshot,
            where: s.state != :pending_deletion,
            order_by: [desc: s.inserted_at]
          )
      ]
    )
    |> Repo.all()
  end

  @doc "Gets a snapshot by its ID."
  def get_snapshot_by_id(id) do
    Repo.get(Snapshot, id)
  end

  @doc "Creates a new snapshot for a link."
  def create_snapshot(link_id, user_id, job_id, attrs \\ %{}) do
    %Snapshot{link_id: link_id, user_id: user_id, job_id: job_id}
    |> Snapshot.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns a snapshot by link_id and job_id, or nil."
  def get_snapshot(link_id, job_id) do
    Snapshot
    |> Repo.get_by(link_id: link_id, job_id: job_id)
  end

  @doc "Updates a snapshot's attributes."
  def update_snapshot(%Snapshot{} = snapshot, attrs) do
    snapshot
    |> Snapshot.update_changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns total storage bytes used across all users (complete snapshots only)."
  def storage_used do
    Snapshot
    |> where(state: :complete)
    |> Repo.aggregate(:sum, :file_size_bytes)
    |> to_integer()
  end

  @doc "Returns total storage bytes used by a specific user (complete snapshots only)."
  def storage_used_by_user(user_id) do
    Snapshot
    |> where(user_id: ^user_id)
    |> where(state: :complete)
    |> Repo.aggregate(:sum, :file_size_bytes)
    |> to_integer()
  end

  @doc "Marks all snapshots and archives for a link as pending deletion."
  def mark_snapshots_for_deletion(link_id) do
    # Also mark archives for this link
    from(a in Archive, where: a.link_id == ^link_id)
    |> Repo.update_all(set: [state: :pending_deletion])

    Snapshot
    |> where(link_id: ^link_id)
    |> Repo.update_all(set: [state: :pending_deletion])
  end

  @doc """
  Enqueues a `SnapshotDeleter` job for each snapshot in `pending_deletion` state.
  Also cleans up orphaned archives in `pending_deletion` state.
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

    # Clean up orphaned archives (pending_deletion with no remaining snapshots)
    orphaned_archive_ids =
      from(a in Archive,
        where: a.state == :pending_deletion,
        left_join: s in Snapshot,
        on: s.archive_id == a.id and s.state != :pending_deletion,
        where: is_nil(s.id),
        select: a.id
      )
      |> Repo.all()

    if orphaned_archive_ids != [] do
      from(a in Archive, where: a.id in ^orphaned_archive_ids)
      |> Repo.delete_all()
    end

    :ok
  end

  @doc """
  Deletes a single snapshot's storage and database record.
  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  def delete_snapshot(snapshot_id) when is_integer(snapshot_id) do
    case Repo.get(Snapshot, snapshot_id) do
      %Snapshot{state: :pending_deletion} = snapshot ->
        with :ok <- delete_snapshot_storage(snapshot),
             {:ok, _} <- Repo.delete(snapshot) do
          :ok
        end

      _ ->
        :ok
    end
  end

  defp delete_snapshot_storage(%Snapshot{storage_key: nil}), do: :ok
  defp delete_snapshot_storage(%Snapshot{storage_key: key}), do: Storage.delete(key)

  @doc """
  Lists unarchived links for a user (links without completed snapshots
  and without an active archive in progress).
  """
  def list_unarchived_links_for_user(%User{} = user, limit \\ 50) do
    from(l in Link,
      left_join: s in Snapshot,
      on: l.id == s.link_id and s.state == :complete,
      left_join: a in Archive,
      on: l.id == a.link_id and a.state == :active,
      where: l.user_id == ^user.id and is_nil(s.id) and is_nil(a.id),
      order_by: [asc: l.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Merges archive pipeline steps with crawler steps from snapshots into a
  single chronological timeline. Each crawler step is annotated with a
  `"prefix"` key (the crawler type, e.g. "singlefile") so the timeline
  component can show which crawler a step belongs to.

  Archive-level steps (created, preflight, dispatched, failed) have no prefix.
  """
  def merge_timeline(archive_steps, snapshots) when is_list(snapshots) do
    archive_entries = archive_steps || []

    crawler_entries =
      Enum.flat_map(snapshots, fn snapshot ->
        prefix = snapshot_type(snapshot)

        crawl_steps(snapshot)
        |> Enum.map(&Map.put(&1, "prefix", prefix))
      end)

    archive_entries ++ crawler_entries
  end

  defp snapshot_type(%{type: type}), do: type
  defp snapshot_type(_), do: "unknown"

  defp crawl_steps(%{crawl_info: %{"steps" => steps}}) when is_list(steps), do: steps
  defp crawl_steps(_), do: []

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_integer(n) when is_integer(n), do: n
end
