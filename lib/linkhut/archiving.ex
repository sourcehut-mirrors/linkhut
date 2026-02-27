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
  alias Linkhut.Archiving.{Archive, Snapshot, Steps, Storage, Tokens}
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

  @doc "Creates a new archive record."
  def create_archive(attrs) do
    %Archive{}
    |> Archive.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Transitions a `:pending` archive to `:processing`.
  Idempotent for already-processing archives (safe for Oban retries).
  Returns `{:error, :not_found}` if the archive doesn't exist or is in
  an unexpected state.
  """
  def start_processing(archive_id) do
    case Repo.get(Archive, archive_id) do
      %Archive{state: :pending} = archive ->
        update_archive(archive, %{state: :processing})

      %Archive{state: :processing} = archive ->
        {:ok, archive}

      _ ->
        {:error, :not_found}
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

    Repo.transaction(fn ->
      archive_query =
        from(a in Archive,
          where: a.link_id == ^link_id and a.state in [:pending, :processing, :complete, :failed]
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
    end)

    :ok
  end

  @doc """
  Schedules a re-crawl for a link by enqueueing a new Archiver job
  with the recrawl flag.
  """
  def schedule_recrawl(link) do
    Linkhut.Archiving.Workers.Archiver.enqueue(link, recrawl: true, schedule_in: 10)
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
  def create_snapshot(link_id, user_id, attrs \\ %{}) do
    %Snapshot{link_id: link_id, user_id: user_id}
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
    Repo.transaction(fn ->
      from(a in Archive, where: a.link_id == ^link_id and a.state != :pending_deletion)
      |> Repo.update_all(set: [state: :pending_deletion])

      from(s in Snapshot, where: s.link_id == ^link_id and s.state != :pending_deletion)
      |> Repo.update_all(set: [state: :pending_deletion])
    end)

    :ok
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
        do_delete_snapshot(snapshot)

      _ ->
        :ok
    end
  end

  defp do_delete_snapshot(snapshot) do
    with :ok <- delete_snapshot_storage(snapshot),
         {:ok, _} <- Repo.delete(snapshot) do
      if snapshot.archive_id, do: recompute_archive_size_by_id(snapshot.archive_id)
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
      on: l.id == a.link_id and a.state in [:pending, :processing, :complete],
      where: l.user_id == ^user.id and is_nil(s.id) and is_nil(a.id),
      order_by: [desc: l.inserted_at],
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

  @doc "Extracts crawl steps from a snapshot's crawl_info."
  def crawl_steps(%{crawl_info: %{"steps" => steps}}) when is_list(steps), do: steps
  def crawl_steps(_), do: []

  @doc """
  Atomically recomputes the `total_size_bytes` for a single archive
  from its complete snapshots.
  """
  def recompute_archive_size(%Archive{id: archive_id}) do
    recompute_archive_size_by_id(archive_id)
  end

  @doc """
  Atomically recomputes the `total_size_bytes` for an archive by ID.
  Uses a single UPDATE ... SET ... = (SELECT ...) statement — no locks needed.
  """
  def recompute_archive_size_by_id(nil), do: :ok

  def recompute_archive_size_by_id(archive_id) when is_integer(archive_id) do
    Repo.query!(
      "UPDATE archives SET total_size_bytes = (SELECT COALESCE(SUM(file_size_bytes), 0) FROM snapshots WHERE archive_id = $1 AND state = 'complete') WHERE id = $1",
      [archive_id]
    )

    :ok
  end

  @doc """
  Transitions a `:processing` archive to `:complete` when all its snapshots
  have reached a terminal state (`:complete`, `:failed`, or `:pending_deletion`).

  Uses atomic `UPDATE ... WHERE state = :processing` to prevent race conditions
  when concurrent crawlers finish simultaneously.
  """
  def maybe_complete_archive(archive_id) when is_integer(archive_id) do
    %{num_rows: count} =
      Repo.query!(
        """
        UPDATE archives SET state = 'complete', lock_version = lock_version + 1, updated_at = NOW()
        WHERE id = $1 AND state = 'processing'
        AND EXISTS (
          SELECT 1 FROM snapshots WHERE archive_id = $1 AND state != 'pending_deletion'
        )
        AND NOT EXISTS (
          SELECT 1 FROM snapshots WHERE archive_id = $1
          AND state NOT IN ('complete', 'failed', 'pending_deletion')
        )
        """,
        [archive_id]
      )

    if count == 1 do
      case Repo.get(Archive, archive_id) do
        nil ->
          :ok

        archive ->
          update_archive(archive, %{
            steps: Steps.append_step(archive.steps, "completed", %{"msg" => "completed"})
          })
      end
    else
      :ok
    end
  end

  def maybe_complete_archive(_), do: :ok

  @doc """
  Atomically recomputes `total_size_bytes` for all archives
  using a single correlated subquery UPDATE.
  """
  def recompute_all_archive_sizes do
    Repo.query!("""
    UPDATE archives
    SET total_size_bytes = (
      SELECT COALESCE(SUM(file_size_bytes), 0)
      FROM snapshots
      WHERE snapshots.archive_id = archives.id
        AND snapshots.state = 'complete'
    )
    """)

    :ok
  end

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_integer(n) when is_integer(n), do: n
end
