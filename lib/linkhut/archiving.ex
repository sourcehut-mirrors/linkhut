defmodule Linkhut.Archiving do
  @moduledoc """
  Manages link archiving — creating snapshots of bookmarked pages,
  storing them, and generating time-limited tokens to view them.

  Crawling is handled by `Linkhut.Archiving.Workers.Archiver` and
  `Linkhut.Archiving.Workers.Crawler`, which call back into this context
  to persist results.
  """

  import Ecto.Query

  alias Linkhut.Accounts
  alias Linkhut.Accounts.User
  alias Linkhut.Archiving.{CrawlRun, Snapshot, Steps, Storage, Tokens}
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

  # --- User stats ---

  @doc "Returns archive statistics for a user."
  def archive_stats_for_user(%User{} = user) do
    breakdown = snapshot_breakdown(user.id)

    %{
      archived_links: archived_links(user.id),
      pending_links: pending_links(user.id),
      total_snapshots: breakdown |> Enum.map(& &1.total_count) |> Enum.sum(),
      snapshot_breakdown: breakdown,
      total_storage_bytes: breakdown |> Enum.map(& &1.total_size) |> Enum.sum()
    }
  end

  defp archived_links(user_id) do
    Snapshot
    |> where(user_id: ^user_id, state: :complete)
    |> select([s], count(s.link_id, :distinct))
    |> Repo.one()
  end

  defp pending_links(user_id) do
    CrawlRun
    |> where([a], a.user_id == ^user_id and a.state in [:pending, :processing])
    |> select([a], count(a.link_id, :distinct))
    |> Repo.one()
  end

  # --- Admin stats ---

  @doc "Returns comprehensive archive statistics for the admin dashboard."
  def admin_archive_stats do
    %{
      mode: mode(),
      total_storage_bytes: storage_used(),
      crawls_by_state: crawls_by_state(),
      snapshot_breakdown: snapshot_breakdown(nil),
      queue_depths: queue_depths(),
      recent_failures: recent_failure_summary(),
      top_users: top_users_by_storage(10),
      stale_work: stale_work_counts()
    }
  end

  defp crawls_by_state do
    CrawlRun
    |> group_by(:state)
    |> select([a], {a.state, count(a.id)})
    |> Repo.all()
  end

  defp snapshot_breakdown(user_id) do
    Snapshot
    |> then(fn q -> if user_id, do: where(q, user_id: ^user_id), else: q end)
    |> group_by([s], [s.format, s.state])
    |> select([s], %{
      format: s.format,
      state: s.state,
      count: count(s.id),
      size: coalesce(sum(s.file_size_bytes), 0)
    })
    |> order_by([s], [s.format, s.state])
    |> Repo.all()
    |> Enum.map(fn row -> %{row | size: to_integer(row.size)} end)
    |> Enum.group_by(& &1.format)
    |> Enum.sort_by(fn {format, _} -> format end)
    |> Enum.map(fn {format, rows} ->
      %{
        format: format,
        states: Enum.map(rows, &{&1.state, &1.count, &1.size}),
        total_count: rows |> Enum.map(& &1.count) |> Enum.sum(),
        total_size: rows |> Enum.map(& &1.size) |> Enum.sum()
      }
    end)
  end

  defp queue_depths do
    Oban.Job
    |> where([j], j.queue in ["archiver", "crawler"])
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
    stale_crawls =
      CrawlRun
      |> where([a], a.state == :processing and a.updated_at < ago(1, "hour"))
      |> Repo.aggregate(:count)

    stale_snapshots =
      Snapshot
      |> where([s], s.state == :crawling and s.updated_at < ago(1, "hour"))
      |> Repo.aggregate(:count)

    %{stale_crawls: stale_crawls, stale_snapshots: stale_snapshots}
  end

  @doc "Generates a short-lived token for serving a snapshot."
  def generate_token(snapshot_id), do: Tokens.generate_token(snapshot_id)

  @doc "Verifies a snapshot serving token, returning the snapshot_id or an error."
  def verify_token(token), do: Tokens.verify_token(token)

  # --- CrawlRun functions ---

  @doc "Creates a new crawl run record."
  def create_crawl_run(attrs) do
    %CrawlRun{}
    |> CrawlRun.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Transitions a `:pending` crawl run to `:processing`.
  Idempotent for already-processing crawl runs (safe for Oban retries).
  Returns `{:error, :not_found}` if the crawl run doesn't exist or is in
  an unexpected state.
  """
  def start_processing(crawl_run_id) do
    case Repo.get(CrawlRun, crawl_run_id) do
      %CrawlRun{state: :pending} = crawl_run ->
        update_crawl_run(crawl_run, %{state: :processing})

      %CrawlRun{state: :processing} = crawl_run ->
        {:ok, crawl_run}

      _ ->
        {:error, :not_found}
    end
  end

  @doc "Updates a crawl run's attributes."
  def update_crawl_run(%CrawlRun{} = crawl_run, attrs) do
    crawl_run
    |> CrawlRun.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Cleans up older snapshots of the same `(link_id, type)` that are superseded
  by a newly-terminal snapshot.

  Quality ordering — a new state supersedes older snapshots in these states:

  - `:complete`      → `:complete`, `:not_available`, `:failed`
  - `:not_available` → `:not_available`, `:failed`
  - `:failed`        → `:failed`

  Also marks crawl runs that end up with zero remaining non-deleted snapshots
  as `:pending_deletion`.
  """
  def cleanup_superseded_snapshots(snapshot_id, link_id, format, new_state, new_source) do
    superseded_states = superseded_states(new_state)

    if superseded_states == [] do
      :ok
    else
      do_cleanup_superseded(snapshot_id, link_id, format, superseded_states, new_source)
    end
  end

  defp superseded_states(:complete), do: [:complete, :not_available, :failed]
  defp superseded_states(:not_available), do: [:not_available, :failed]
  defp superseded_states(:failed), do: [:failed]
  defp superseded_states(_), do: []

  defp do_cleanup_superseded(snapshot_id, link_id, format, superseded_states, new_source) do
    # Mark older snapshots of the same (link_id, format) as pending_deletion.
    # System sources don't supersede uploads (different source lineage).
    base_query =
      from(s in Snapshot,
        where:
          s.link_id == ^link_id and
            s.format == ^format and
            s.state in ^superseded_states and
            s.id != ^snapshot_id
      )

    query =
      if new_source != "upload" do
        from(s in base_query, where: s.source != "upload")
      else
        base_query
      end

    {_count, affected_crawl_run_ids} =
      from(s in query, select: s.crawl_run_id)
      |> Repo.update_all(set: [state: :pending_deletion])

    # Mark crawl runs that now have zero non-deleted snapshots
    crawl_run_ids =
      affected_crawl_run_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if crawl_run_ids != [] do
      orphaned =
        from(cr in CrawlRun,
          as: :cr,
          where: cr.id in ^crawl_run_ids and cr.state != :pending_deletion,
          where:
            not exists(
              from(s in Snapshot,
                where: s.crawl_run_id == parent_as(:cr).id and s.state != :pending_deletion
              )
            ),
          select: cr.id
        )
        |> Repo.all()

      if orphaned != [] do
        from(cr in CrawlRun, where: cr.id in ^orphaned)
        |> Repo.update_all(set: [state: :pending_deletion])
      end
    end

    :ok
  end

  @doc """
  Schedules a re-crawl for a link by enqueueing a new Archiver job
  with the recrawl flag.
  """
  def schedule_recrawl(link) do
    Linkhut.Archiving.Workers.Archiver.enqueue(link,
      recrawl: true,
      schedule_in: 10
    )
  end

  # --- Snapshot functions ---

  @doc "Returns a complete snapshot by ID, or `{:error, :not_found}`."
  def get_complete_snapshot(id) do
    case Repo.get(Snapshot, id) do
      %Snapshot{state: :complete} = snapshot -> {:ok, snapshot}
      _ -> {:error, :not_found}
    end
  end

  @doc "Returns all complete snapshots for a link, newest first, with crawl_run preloaded."
  def get_complete_snapshots_by_link(link_id) do
    Snapshot
    |> where(link_id: ^link_id, state: :complete)
    |> order_by([s], desc: s.inserted_at)
    |> preload(:crawl_run)
    |> Repo.all()
  end

  @doc "Returns the latest complete snapshot of a given format for a link."
  def get_latest_complete_snapshot(link_id, format) do
    case Snapshot
         |> where(link_id: ^link_id, format: ^format, state: :complete)
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
  Returns all crawl runs for a link (excluding pending_deletion),
  with preloaded snapshots (also excluding pending_deletion), newest first.
  """
  def get_crawl_runs_by_link(link_id) do
    from(cr in CrawlRun,
      where: cr.link_id == ^link_id and cr.state != :pending_deletion,
      order_by: [desc: cr.inserted_at],
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

  @doc "Marks all snapshots and crawl runs for a link as pending deletion."
  def mark_snapshots_for_deletion(link_id) do
    Repo.transaction(fn ->
      from(cr in CrawlRun, where: cr.link_id == ^link_id and cr.state != :pending_deletion)
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

    # Clean up orphaned crawl runs (pending_deletion with no remaining snapshots)
    orphaned_crawl_run_ids =
      from(cr in CrawlRun,
        where: cr.state == :pending_deletion,
        left_join: s in Snapshot,
        on: s.crawl_run_id == cr.id and s.state != :pending_deletion,
        where: is_nil(s.id),
        select: cr.id
      )
      |> Repo.all()

    if orphaned_crawl_run_ids != [] do
      from(cr in CrawlRun, where: cr.id in ^orphaned_crawl_run_ids)
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
      if snapshot.crawl_run_id, do: recompute_crawl_run_size_by_id(snapshot.crawl_run_id)
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
      left_join: cr in CrawlRun,
      on:
        l.id == cr.link_id and
          cr.state in [:pending, :processing, :complete, :not_archivable, :failed],
      where: l.user_id == ^user.id and is_nil(s.id) and is_nil(cr.id),
      order_by: [desc: l.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns links that have configured sources not covered by a current
  snapshot with matching version, excluding links with in-flight crawl runs.

  Returns a list of `{link, remaining_sources}` tuples where `remaining_sources`
  is a `MapSet` of crawler source type strings not yet covered by any snapshot.
  """
  def list_reconcilable_links(%User{} = user, limit \\ 100) do
    configured_crawlers = Linkhut.Config.archiving(:crawlers, [])

    if configured_crawlers == [] do
      []
    else
      expected_sources = build_expected_sources(configured_crawlers)

      user.id
      |> fetch_uncovered_links(expected_sources)
      |> Enum.take(limit)
    end
  end

  defp build_expected_sources(crawlers) do
    Enum.map(crawlers, fn module ->
      {module.source_type(), module.module_version()}
    end)
  end

  defp fetch_uncovered_links(user_id, expected_sources) do
    # All links for this user that have at least one crawl run (i.e., were archived before)
    # and have no in-flight crawl runs
    archived_link_ids = archived_link_ids_without_inflight(user_id)

    if archived_link_ids == [] do
      []
    else
      do_fetch_uncovered(archived_link_ids, expected_sources)
    end
  end

  defp archived_link_ids_without_inflight(user_id) do
    from(l in Link,
      join: cr in CrawlRun, on: cr.link_id == l.id,
      left_join: inflight in CrawlRun,
        on: inflight.link_id == l.id and inflight.state in [:pending, :processing],
      where: l.user_id == ^user_id and is_nil(inflight.id),
      distinct: true,
      select: l.id
    )
    |> Repo.all()
  end

  defp do_fetch_uncovered(link_ids, expected_sources) do
    # Get covered {source, version} pairs per link from existing snapshots
    covered_by_link = covered_sources_by_link(link_ids)

    expected_set = MapSet.new(expected_sources)

    link_ids
    |> Enum.map(fn link_id ->
      covered = Map.get(covered_by_link, link_id, MapSet.new())
      missing = MapSet.difference(expected_set, covered)
      # Extract just the source names for the missing ones
      missing_sources = MapSet.new(missing, fn {source, _version} -> source end)
      {link_id, missing_sources}
    end)
    |> Enum.reject(fn {_link_id, missing} -> MapSet.size(missing) == 0 end)
    |> load_links()
  end

  defp covered_sources_by_link(link_ids) when link_ids == [], do: %{}

  defp covered_sources_by_link(link_ids) do
    Snapshot
    |> where([s], s.link_id in ^link_ids)
    |> where([s], s.state in [:complete, :not_available, :pending, :crawling, :retryable])
    |> select([s], {s.link_id, s.source, fragment("?->>'version'", s.crawler_meta)})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_link_id, source, version} -> {source, version} end)
    |> Map.new(fn {link_id, pairs} -> {link_id, MapSet.new(pairs)} end)
  end

  defp load_links(link_id_missing_pairs) do
    link_ids = Enum.map(link_id_missing_pairs, &elem(&1, 0))
    missing_by_id = Map.new(link_id_missing_pairs)

    Link
    |> where([l], l.id in ^link_ids)
    |> Repo.all()
    |> Enum.map(fn link -> {link, Map.fetch!(missing_by_id, link.id)} end)
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
        prefix = snapshot_source(snapshot)
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

  defp snapshot_source(%{source: source}), do: source
  defp snapshot_source(_), do: "unknown"

  @doc "Extracts crawl steps from a snapshot's crawl_info."
  def crawl_steps(%{crawl_info: %{"steps" => steps}}) when is_list(steps), do: steps
  def crawl_steps(_), do: []

  @doc """
  Atomically recomputes the `total_size_bytes` for a single crawl run
  from its complete snapshots.
  """
  def recompute_crawl_run_size(%CrawlRun{id: crawl_run_id}) do
    recompute_crawl_run_size_by_id(crawl_run_id)
  end

  @doc """
  Atomically recomputes the `total_size_bytes` for a crawl run by ID.
  Uses a single UPDATE ... SET ... = (SELECT ...) statement — no locks needed.
  """
  def recompute_crawl_run_size_by_id(nil), do: :ok

  def recompute_crawl_run_size_by_id(crawl_run_id) when is_integer(crawl_run_id) do
    Repo.query!(
      "UPDATE crawl_runs SET total_size_bytes = (SELECT COALESCE(SUM(file_size_bytes), 0) FROM snapshots WHERE crawl_run_id = $1 AND state = 'complete') WHERE id = $1",
      [crawl_run_id]
    )

    :ok
  end

  @doc """
  Transitions a `:processing` crawl run to `:complete` when all its snapshots
  have reached a terminal state (`:complete`, `:not_available`, `:failed`,
  or `:pending_deletion`).

  Uses atomic `UPDATE ... WHERE state = :processing` to prevent race conditions
  when concurrent crawlers finish simultaneously.
  """
  def maybe_complete_crawl_run(crawl_run_id) when is_integer(crawl_run_id) do
    %{num_rows: count} =
      Repo.query!(
        """
        UPDATE crawl_runs SET state = 'complete', lock_version = lock_version + 1, updated_at = NOW()
        WHERE id = $1 AND state = 'processing'
        AND EXISTS (
          SELECT 1 FROM snapshots WHERE crawl_run_id = $1 AND state != 'pending_deletion'
        )
        AND NOT EXISTS (
          SELECT 1 FROM snapshots WHERE crawl_run_id = $1
          AND state NOT IN ('complete', 'not_available', 'failed', 'pending_deletion')
        )
        """,
        [crawl_run_id]
      )

    if count == 1 do
      case Repo.get(CrawlRun, crawl_run_id) do
        nil ->
          :ok

        crawl_run ->
          update_crawl_run(crawl_run, %{
            steps: Steps.append_step(crawl_run.steps, "completed", %{"msg" => "completed"})
          })
      end
    else
      :ok
    end
  end

  def maybe_complete_crawl_run(_), do: :ok

  # --- Scheduler helpers ---

  @doc """
  Returns a `MapSet` of domain strings that have had a crawl run created
  within the cooldown window. Used by the scheduler to skip domains that
  were recently crawled.
  """
  def domains_on_cooldown(cooldown_seconds \\ @domain_cooldown_seconds) do
    cutoff = DateTime.add(DateTime.utc_now(), -cooldown_seconds)

    from(cr in CrawlRun,
      where: cr.inserted_at > ^cutoff and cr.state != :pending_deletion,
      select: cr.url
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
