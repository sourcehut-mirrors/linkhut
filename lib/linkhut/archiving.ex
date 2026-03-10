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
  alias Linkhut.{Repo, Subscriptions}

  @domain_cooldown_seconds 120

  @doc """
  Returns the archiving mode.

  - `:disabled` — no archiving features
  - `:enabled` — archiving for all active users
  - `:limited` — archiving only for active paying users
  """
  def mode, do: Linkhut.Config.archiving(:mode, :disabled)

  @doc "Returns true if the user can create new archives."
  @spec can_create_archives?(User.t()) :: boolean()
  def can_create_archives?(%User{type: type} = user)
      when type in [:active, :active_free, :active_paying] do
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
  def can_view_archives?(%User{type: type})
      when type in [:active, :active_free, :active_paying] do
    mode() != :disabled
  end

  def can_view_archives?(_), do: false

  # --- User stats ---

  @doc "Returns archive statistics for a user."
  def archive_stats_for_user(%User{} = user) do
    snapshots_by_type = snapshot_stats_by_type(user.id)

    %{
      archived_links: archived_links(user.id),
      pending_links: pending_links(user.id),
      snapshots_by_type: snapshots_by_type,
      total_storage_bytes: snapshots_by_type |> Enum.map(& &1.size) |> Enum.sum()
    }
  end

  defp archived_links(user_id) do
    Snapshot
    |> where(user_id: ^user_id, state: :complete)
    |> select([s], count(s.link_id, :distinct))
    |> Repo.one()
  end

  defp pending_links(user_id) do
    Archive
    |> where([a], a.user_id == ^user_id and a.state in [:pending, :processing])
    |> select([a], count(a.link_id, :distinct))
    |> Repo.one()
  end

  defp snapshot_stats_by_type(user_id \\ nil) do
    Snapshot
    |> where(state: :complete)
    |> then(fn q -> if user_id, do: where(q, user_id: ^user_id), else: q end)
    |> group_by(:type)
    |> select([s], {s.type, count(s.id), coalesce(sum(s.file_size_bytes), 0)})
    |> Repo.all()
    |> Enum.map(fn {type, count, size} -> %{type: type, count: count, size: to_integer(size)} end)
  end

  # --- Admin stats ---

  @doc "Returns comprehensive archive statistics for the admin dashboard."
  def admin_archive_stats do
    %{
      mode: mode(),
      total_storage_bytes: storage_used(),
      archives_by_state: archives_by_state(),
      snapshots_by_state: snapshots_by_state(),
      snapshots_by_type: snapshot_stats_by_type(),
      queue_depths: queue_depths(),
      recent_failures: recent_failure_summary(),
      top_users: top_users_by_storage(10),
      stale_work: stale_work_counts()
    }
  end

  defp archives_by_state do
    Archive
    |> group_by(:state)
    |> select([a], {a.state, count(a.id)})
    |> Repo.all()
  end

  defp snapshots_by_state do
    Snapshot
    |> group_by(:state)
    |> select([s], {s.state, count(s.id)})
    |> Repo.all()
  end

  defp queue_depths do
    Oban.Job
    |> where([j], j.queue in ["archiver", "crawler", "wayback"])
    |> where([j], j.state in ["available", "scheduled", "executing", "retryable"])
    |> group_by([j], [j.queue, j.state])
    |> select([j], %{queue: j.queue, state: j.state, count: count()})
    |> Repo.all()
  end

  defp recent_failure_summary do
    Snapshot
    |> where([s], s.state == :failed and s.failed_at > ago(24, "hour"))
    |> group_by([s], fragment("coalesce(?->>'error', '(no message)')", s.archive_metadata))
    |> select([s], %{
      error: fragment("coalesce(?->>'error', '(no message)')", s.archive_metadata),
      count: count()
    })
    |> order_by(desc: count())
    |> limit(10)
    |> Repo.all()
  end

  defp top_users_by_storage(n) do
    Snapshot
    |> where([s], s.state == :complete)
    |> join(:inner, [s], u in User, on: s.user_id == u.id)
    |> group_by([s, u], [u.id, u.username])
    |> select([s, u], %{username: u.username, bytes: sum(s.file_size_bytes)})
    |> order_by([s], desc: sum(s.file_size_bytes))
    |> limit(^n)
    |> Repo.all()
    |> Enum.map(fn row -> %{row | bytes: to_integer(row.bytes)} end)
  end

  defp stale_work_counts do
    stale_archives =
      Archive
      |> where([a], a.state == :processing and a.updated_at < ago(1, "hour"))
      |> Repo.aggregate(:count)

    stale_snapshots =
      Snapshot
      |> where([s], s.state == :crawling and s.updated_at < ago(1, "hour"))
      |> Repo.aggregate(:count)

    %{stale_archives: stale_archives, stale_snapshots: stale_snapshots}
  end

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
  and without an existing archive).
  """
  def list_unarchived_links_for_user(%User{} = user, limit \\ 50) do
    from(l in Link,
      left_join: s in Snapshot,
      on: l.id == s.link_id and s.state == :complete,
      left_join: a in Archive,
      on: l.id == a.link_id and a.state in [:pending, :processing, :complete, :failed],
      where: l.user_id == ^user.id and is_nil(s.id) and is_nil(a.id),
      order_by: [desc: l.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Merges archive pipeline steps with crawler steps from snapshots into a
  single chronological timeline, sorted by timestamp.

  Each crawler step is annotated with a `"prefix"` key (the crawler type,
  e.g. "singlefile") so the timeline component can show which crawler a
  step belongs to. Archive-level steps have no prefix.

  Steps from the same crawler are kept together as a group — sorted among
  archive steps by the timestamp of the group's first entry. Crawler
  steps receive a `"group"` integer (starting at 1) identifying their
  group; archive steps have no `"group"` key.
  """
  def merge_timeline(archive_steps, snapshots) when is_list(snapshots) do
    archive_groups =
      (archive_steps || [])
      |> Enum.map(&{:archive, [&1]})

    crawler_groups =
      snapshots
      |> Enum.flat_map(fn snapshot ->
        prefix = snapshot_type(snapshot)
        steps = crawl_steps(snapshot) |> Enum.map(&Map.put(&1, "prefix", prefix))
        if steps == [], do: [], else: [{:crawler, steps}]
      end)

    (archive_groups ++ crawler_groups)
    |> Enum.sort_by(fn {_, [first | _]} -> first["at"] || "" end)
    |> assign_crawler_groups(1, [])
    |> List.flatten()
  end

  defp assign_crawler_groups([], _n, acc), do: Enum.reverse(acc)

  defp assign_crawler_groups([{:archive, steps} | rest], n, acc) do
    assign_crawler_groups(rest, n, [steps | acc])
  end

  defp assign_crawler_groups([{:crawler, steps} | rest], n, acc) do
    tagged = Enum.map(steps, &Map.put(&1, "group", n))
    assign_crawler_groups(rest, n + 1, [tagged | acc])
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

  # --- Scheduler helpers ---

  @doc """
  Returns a `MapSet` of domain strings that have had an archive created
  within the cooldown window. Used by the scheduler to skip domains that
  were recently crawled.
  """
  def domains_on_cooldown(cooldown_seconds \\ @domain_cooldown_seconds) do
    cutoff = DateTime.add(DateTime.utc_now(), -cooldown_seconds)

    from(a in Archive,
      where: a.inserted_at > ^cutoff and a.state != :pending_deletion,
      select: a.url
    )
    |> Repo.all()
    |> Enum.map(&extract_domain/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @doc """
  Returns the number of available slots in the archiver queue.
  Counts jobs in active states and subtracts from the queue limit.
  """
  def available_archiver_slots do
    queue_limit = archiver_queue_limit()

    active =
      from(j in Oban.Job,
        where: j.queue == "archiver",
        where: j.state in ["available", "scheduled", "executing", "retryable"],
        select: count(j.id)
      )
      |> Repo.one()

    max(queue_limit - active, 0)
  end

  @doc false
  def extract_domain(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> nil
    end
  end

  def extract_domain(_), do: nil

  defp archiver_queue_limit do
    case Application.get_env(:linkhut, Oban)[:queues] do
      queues when is_list(queues) -> Keyword.get(queues, :archiver, 5)
      _ -> 5
    end
  end

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_integer(n) when is_integer(n), do: n
end
