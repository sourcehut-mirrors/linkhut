defmodule Linkhut.ArchivingTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Snapshot

  describe "can_create_archives?/1" do
    test "returns false when disabled, and true for active users when enabled" do
      user = insert(:user, type: :active)

      for {mode, expected} <- [disabled: false, enabled: true] do
        put_override(Linkhut.Archiving, :mode, mode)
        assert Archiving.can_create_archives?(user) == expected, "for #{mode}"
      end

      assert Archiving.can_create_archives?(%Linkhut.Accounts.User{type: :unconfirmed}) == false
      assert Archiving.can_create_archives?(nil) == false
    end

    test "returns true only for users with active supporter subscription when limited" do
      put_override(Linkhut.Archiving, :mode, :limited)

      user_with_sub = insert(:user, type: :active)
      insert(:subscription, user_id: user_with_sub.id, plan: :supporter, status: :active)
      assert Archiving.can_create_archives?(user_with_sub) == true

      user_without_sub = insert(:user, type: :active)
      assert Archiving.can_create_archives?(user_without_sub) == false
    end
  end

  describe "can_view_archives?/1" do
    test "returns false when disabled, and true for active users otherwise" do
      for {mode, expected} <- [disabled: false, enabled: true, limited: true] do
        put_override(Linkhut.Archiving, :mode, mode)

        assert Archiving.can_view_archives?(%Linkhut.Accounts.User{type: :active}) == expected,
               "for #{mode}"
      end

      assert Archiving.can_view_archives?(%Linkhut.Accounts.User{type: :unconfirmed}) == false
      assert Archiving.can_view_archives?(nil) == false
    end
  end

  describe "mark_snapshots_for_deletion/1" do
    test "marks all snapshots for a link as pending_deletion" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      other = insert(:snapshot, user_id: user.id, state: :complete)

      s1 = insert(:snapshot, user_id: user.id, link_id: link.id, state: :complete)
      s2 = insert(:snapshot, user_id: user.id, link_id: link.id, state: :pending)

      assert :ok = Archiving.mark_snapshots_for_deletion(link.id)

      assert Repo.get(Snapshot, s1.id).state == :pending_deletion
      assert Repo.get(Snapshot, s2.id).state == :pending_deletion
      assert Repo.get(Snapshot, other.id).state == :complete
    end
  end

  describe "enqueue_pending_deletions/0" do
    test "enqueues a SnapshotDeleter job for each pending_deletion snapshot" do
      s1 = insert(:snapshot, state: :pending_deletion)
      s2 = insert(:snapshot, state: :pending_deletion)
      complete = insert(:snapshot, state: :complete)

      assert :ok = Archiving.enqueue_pending_deletions()

      assert_enqueued(
        worker: Linkhut.Archiving.Workers.SnapshotDeleter,
        args: %{"snapshot_id" => s1.id}
      )

      assert_enqueued(
        worker: Linkhut.Archiving.Workers.SnapshotDeleter,
        args: %{"snapshot_id" => s2.id}
      )

      refute_enqueued(
        worker: Linkhut.Archiving.Workers.SnapshotDeleter,
        args: %{"snapshot_id" => complete.id}
      )
    end
  end

  describe "delete_snapshot/1" do
    @data_dir Linkhut.Config.archiving(:data_dir)

    setup do
      File.rm_rf!(@data_dir)
      File.mkdir_p!(@data_dir)
      on_exit(fn -> File.rm_rf(@data_dir) end)
      :ok
    end

    test "deletes storage and record for pending_deletion snapshot" do
      path = Path.join(@data_dir, "1/100/10/42.singlefile")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "content")

      snapshot = insert(:snapshot, state: :pending_deletion, storage_key: "local:" <> path)

      assert :ok = Archiving.delete_snapshot(snapshot.id)

      assert Repo.get(Snapshot, snapshot.id) == nil
      refute File.exists?(path)
    end

    test "deletes record when storage_key is nil" do
      snapshot = insert(:snapshot, state: :pending_deletion, storage_key: nil)

      assert :ok = Archiving.delete_snapshot(snapshot.id)

      assert Repo.get(Snapshot, snapshot.id) == nil
    end

    test "leaves a snapshot that isn't pending deletion" do
      snapshot = insert(:snapshot, state: :complete)

      assert :ok = Archiving.delete_snapshot(snapshot.id)

      assert Repo.get(Snapshot, snapshot.id)
    end

    test "returns error when storage deletion fails" do
      snapshot = insert(:snapshot, state: :pending_deletion, storage_key: "cloud:bucket/key")

      assert {:error, :invalid_storage_key} = Archiving.delete_snapshot(snapshot.id)

      assert Repo.get(Snapshot, snapshot.id) != nil
    end
  end

  describe "upload_snapshot/3" do
    test "leaves no snapshot behind when storing the file fails" do
      put_override(Linkhut.Archiving, :storage, __MODULE__.FailingStorage)
      link = insert(:link, user_id: insert(:user, credential: build(:credential)).id)
      path = Path.join(System.tmp_dir!(), "upload_#{System.unique_integer([:positive])}.html")
      File.write!(path, "<html>uploaded</html>")
      on_exit(fn -> File.rm(path) end)

      upload = %Plug.Upload{path: path, filename: "page.html", content_type: "text/html"}

      assert {:error, :disk_full} = Archiving.upload_snapshot(link.id, link.user_id, upload)
      assert Linkhut.Repo.all_by(Linkhut.Archiving.Snapshot, link_id: link.id) == []
    end
  end
end

defmodule Linkhut.ArchivingTest.FailingStorage do
  def store(_source, _snapshot, _opts), do: {:error, :disk_full}
end
