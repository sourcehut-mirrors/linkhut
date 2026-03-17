defmodule Linkhut.Archiving.Workers.StaleSnapshotSweeperTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Snapshot
  alias Linkhut.Archiving.Workers.StaleSnapshotSweeper

  defp create_snapshot(user, link, attrs) do
    crawl_run =
      insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, Map.put(attrs, :crawl_run_id, crawl_run.id))

    {snapshot, crawl_run}
  end

  defp age_snapshot(snapshot, minutes) do
    ago = DateTime.add(DateTime.utc_now(), -minutes, :minute)

    Repo.query!("UPDATE snapshots SET updated_at = $1 WHERE id = $2", [ago, snapshot.id])

    Repo.get(Snapshot, snapshot.id)
  end

  test "marks stale :crawling snapshot as :failed" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    {snapshot, _crawl_run} = create_snapshot(user, link, %{state: :crawling})

    age_snapshot(snapshot, 45)

    assert :ok = perform_job(StaleSnapshotSweeper, %{})

    updated = Repo.get(Snapshot, snapshot.id)
    assert updated.state == :failed
  end

  test "marks stale :retryable snapshot as :failed" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    {snapshot, _crawl_run} = create_snapshot(user, link, %{state: :retryable})

    age_snapshot(snapshot, 45)

    assert :ok = perform_job(StaleSnapshotSweeper, %{})

    updated = Repo.get(Snapshot, snapshot.id)
    assert updated.state == :failed
  end

  test "does not mark recent snapshots as failed" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    {snapshot, _crawl_run} = create_snapshot(user, link, %{state: :crawling})

    # Only 5 minutes old — should not be swept
    age_snapshot(snapshot, 5)

    assert :ok = perform_job(StaleSnapshotSweeper, %{})

    updated = Repo.get(Snapshot, snapshot.id)
    assert updated.state == :crawling
  end

  test "does not mark snapshots that have active Oban crawler jobs" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    {snapshot, _crawl_run} = create_snapshot(user, link, %{state: :crawling})

    age_snapshot(snapshot, 45)

    # Insert an active Oban job for this snapshot
    Linkhut.Archiving.Workers.Crawler.new(%{
      "snapshot_id" => snapshot.id,
      "user_id" => user.id,
      "link_id" => link.id,
      "url" => "https://example.com",
      "type" => "singlefile"
    })
    |> Oban.insert!()

    assert :ok = perform_job(StaleSnapshotSweeper, %{})

    updated = Repo.get(Snapshot, snapshot.id)
    assert updated.state == :crawling
  end

  test "calls maybe_complete_crawl_run after marking snapshot failed" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    {snapshot, crawl_run} = create_snapshot(user, link, %{state: :crawling})

    age_snapshot(snapshot, 45)

    assert :ok = perform_job(StaleSnapshotSweeper, %{})

    updated_crawl_run = Repo.get(Linkhut.Archiving.CrawlRun, crawl_run.id)
    assert updated_crawl_run.state == :complete
  end

  test "does not touch :complete or :failed snapshots" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)

    {complete_snapshot, _} =
      create_snapshot(user, link, %{state: :complete, storage_key: "local:/tmp/test"})

    {failed_snapshot, _} = create_snapshot(user, link, %{state: :failed})

    age_snapshot(complete_snapshot, 45)
    age_snapshot(failed_snapshot, 45)

    assert :ok = perform_job(StaleSnapshotSweeper, %{})

    assert Repo.get(Snapshot, complete_snapshot.id).state == :complete
    assert Repo.get(Snapshot, failed_snapshot.id).state == :failed
  end
end
