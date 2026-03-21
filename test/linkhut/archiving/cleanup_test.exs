defmodule Linkhut.Archiving.CleanupTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Snapshot

  defp create_setup do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    {user, link}
  end

  defp create_snapshot_in_run(user, link, {format, source}, state, opts \\ []) do
    crawl_run_state = Keyword.get(opts, :crawl_run_state, :complete)

    crawl_run =
      insert(:crawl_run,
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: crawl_run_state
      )

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, %{
        format: format,
        source: source,
        state: state,
        crawl_run_id: crawl_run.id
      })

    {crawl_run, snapshot}
  end

  @singlefile {"webpage", "singlefile"}
  @wayback {"reference", "wayback"}

  describe "cleanup_superseded_snapshots/5" do
    test "complete supersedes older complete snapshots of the same format and source" do
      {user, link} = create_setup()
      {_old_cr, old_snapshot} = create_snapshot_in_run(user, link, @singlefile, :complete)
      {_new_cr, new_snapshot} = create_snapshot_in_run(user, link, @singlefile, :complete)

      Archiving.cleanup_superseded_snapshots(
        new_snapshot.id,
        link.id,
        "webpage",
        :complete,
        "singlefile"
      )

      assert Repo.get(Snapshot, old_snapshot.id).state == :pending_deletion
      assert Repo.get(Snapshot, new_snapshot.id).state == :complete
    end

    test "complete supersedes older not_available and failed snapshots" do
      {user, link} = create_setup()
      {_, na_snapshot} = create_snapshot_in_run(user, link, @singlefile, :not_available)
      {_, failed_snapshot} = create_snapshot_in_run(user, link, @singlefile, :failed)
      {_, new_snapshot} = create_snapshot_in_run(user, link, @singlefile, :complete)

      Archiving.cleanup_superseded_snapshots(
        new_snapshot.id,
        link.id,
        "webpage",
        :complete,
        "singlefile"
      )

      assert Repo.get(Snapshot, na_snapshot.id).state == :pending_deletion
      assert Repo.get(Snapshot, failed_snapshot.id).state == :pending_deletion
      assert Repo.get(Snapshot, new_snapshot.id).state == :complete
    end

    test "not_available supersedes older not_available and failed but not complete" do
      {user, link} = create_setup()
      {_, complete_snapshot} = create_snapshot_in_run(user, link, @singlefile, :complete)
      {_, na_snapshot} = create_snapshot_in_run(user, link, @singlefile, :not_available)
      {_, failed_snapshot} = create_snapshot_in_run(user, link, @singlefile, :failed)
      {_, new_snapshot} = create_snapshot_in_run(user, link, @singlefile, :not_available)

      Archiving.cleanup_superseded_snapshots(
        new_snapshot.id,
        link.id,
        "webpage",
        :not_available,
        "singlefile"
      )

      assert Repo.get(Snapshot, complete_snapshot.id).state == :complete
      assert Repo.get(Snapshot, na_snapshot.id).state == :pending_deletion
      assert Repo.get(Snapshot, failed_snapshot.id).state == :pending_deletion
      assert Repo.get(Snapshot, new_snapshot.id).state == :not_available
    end

    test "failed only supersedes older failed snapshots" do
      {user, link} = create_setup()
      {_, complete_snapshot} = create_snapshot_in_run(user, link, @singlefile, :complete)
      {_, na_snapshot} = create_snapshot_in_run(user, link, @singlefile, :not_available)
      {_, old_failed} = create_snapshot_in_run(user, link, @singlefile, :failed)
      {_, new_snapshot} = create_snapshot_in_run(user, link, @singlefile, :failed)

      Archiving.cleanup_superseded_snapshots(
        new_snapshot.id,
        link.id,
        "webpage",
        :failed,
        "singlefile"
      )

      assert Repo.get(Snapshot, complete_snapshot.id).state == :complete
      assert Repo.get(Snapshot, na_snapshot.id).state == :not_available
      assert Repo.get(Snapshot, old_failed.id).state == :pending_deletion
      assert Repo.get(Snapshot, new_snapshot.id).state == :failed
    end

    test "does not affect snapshots of different sources" do
      {user, link} = create_setup()
      {_, wayback_snapshot} = create_snapshot_in_run(user, link, @wayback, :complete)
      {_, new_snapshot} = create_snapshot_in_run(user, link, @singlefile, :complete)

      Archiving.cleanup_superseded_snapshots(
        new_snapshot.id,
        link.id,
        "webpage",
        :complete,
        "singlefile"
      )

      assert Repo.get(Snapshot, wayback_snapshot.id).state == :complete
    end

    test "is a no-op for non-terminal states" do
      {user, link} = create_setup()
      {_, old_snapshot} = create_snapshot_in_run(user, link, @singlefile, :complete)
      {_, new_snapshot} = create_snapshot_in_run(user, link, @singlefile, :pending)

      Archiving.cleanup_superseded_snapshots(
        new_snapshot.id,
        link.id,
        "webpage",
        :pending,
        "singlefile"
      )

      assert Repo.get(Snapshot, old_snapshot.id).state == :complete
    end
  end
end
