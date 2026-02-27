defmodule Linkhut.Archiving.Workers.SnapshotDeleterTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Snapshot
  alias Linkhut.Archiving.Workers.SnapshotDeleter

  @data_dir Linkhut.Config.archiving(:data_dir)

  setup do
    File.rm_rf!(@data_dir)
    File.mkdir_p!(@data_dir)
    on_exit(fn -> File.rm_rf(@data_dir) end)
    :ok
  end

  defp create_archive(user, link) do
    insert(:archive, user_id: user.id, link_id: link.id, url: link.url)
  end

  test "deletes storage and database record for pending_deletion snapshot" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    archive = create_archive(user, link)

    path = Path.join(@data_dir, "1/100/10/42.singlefile")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "content")

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, %{
        state: :pending_deletion,
        storage_key: "local:" <> path,
        archive_id: archive.id
      })

    assert :ok = perform_job(SnapshotDeleter, %{"snapshot_id" => snapshot.id})

    assert Repo.get(Snapshot, snapshot.id) == nil
    refute File.exists?(path)
  end

  test "prunes empty parent directories after deletion" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    archive = create_archive(user, link)

    path = Path.join(@data_dir, "1/100/10/42.singlefile")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "content")

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, %{
        state: :pending_deletion,
        storage_key: "local:" <> path,
        archive_id: archive.id
      })

    assert :ok = perform_job(SnapshotDeleter, %{"snapshot_id" => snapshot.id})

    refute File.exists?(Path.join(@data_dir, "1/100/10"))
    refute File.exists?(Path.join(@data_dir, "1/100"))
    refute File.exists?(Path.join(@data_dir, "1"))
    assert File.exists?(@data_dir)
  end

  test "deletes record when storage_key is nil" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    archive = create_archive(user, link)

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, %{
        state: :pending_deletion,
        archive_id: archive.id
      })

    assert :ok = perform_job(SnapshotDeleter, %{"snapshot_id" => snapshot.id})

    assert Repo.get(Snapshot, snapshot.id) == nil
  end

  test "returns :ok when snapshot does not exist (idempotent)" do
    assert :ok = perform_job(SnapshotDeleter, %{"snapshot_id" => 999_999})
  end

  test "returns :ok when snapshot is not in pending_deletion state" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    archive = create_archive(user, link)

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, %{
        state: :complete,
        archive_id: archive.id
      })

    assert :ok = perform_job(SnapshotDeleter, %{"snapshot_id" => snapshot.id})

    # Should not have been deleted
    assert Repo.get(Snapshot, snapshot.id) != nil
  end

  test "returns error when storage deletion fails" do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)
    archive = create_archive(user, link)

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, %{
        state: :pending_deletion,
        storage_key: "cloud:bucket/key",
        archive_id: archive.id
      })

    assert {:error, :invalid_storage_key} =
             perform_job(SnapshotDeleter, %{"snapshot_id" => snapshot.id})

    # Record should still exist for retry
    assert Repo.get(Snapshot, snapshot.id) != nil
  end
end
