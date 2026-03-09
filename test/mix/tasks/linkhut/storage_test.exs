defmodule Mix.Tasks.Linkhut.StorageTest do
  use Linkhut.DataCase, async: false

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Archive, Snapshot, StorageKey}

  @moduletag :mix_task

  @data_dir Linkhut.Config.archiving(:data_dir)

  defp setup_shell(_context) do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp create_complete_snapshot(_context) do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id)

    archive =
      insert(:archive,
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :complete
      )

    content = "<html><body>#{String.duplicate("test content ", 100)}</body></html>"

    File.rm_rf!(@data_dir)
    File.mkdir_p!(@data_dir)
    file_path = Path.join(@data_dir, "snapshot_file")
    File.write!(file_path, content)

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, %{
        type: "singlefile",
        state: :complete,
        storage_key: StorageKey.local(file_path),
        file_size_bytes: byte_size(content),
        processing_time_ms: 100,
        response_code: 200,
        archive_id: archive.id,
        archive_metadata: %{content_type: "text/html"}
      })

    Archiving.recompute_archive_size_by_id(archive.id)

    on_exit(fn -> File.rm_rf(@data_dir) end)

    %{
      user: user,
      link: link,
      archive: archive,
      snapshot: snapshot,
      content: content,
      file_path: file_path
    }
  end

  describe "run/1" do
    setup :setup_shell

    test "shows storage stats" do
      Mix.Tasks.Linkhut.Storage.run([])

      assert_received {:mix_shell, :info, [db_msg]}
      assert db_msg =~ "Storage (DB total):"
      assert_received {:mix_shell, :info, [disk_msg]}
      assert disk_msg =~ "Storage (disk total):"
    end

    test "shows error for invalid arguments" do
      Mix.Tasks.Linkhut.Storage.run(["invalid"])

      assert_received {:mix_shell, :error, [msg]}
      assert msg =~ "Usage:"
    end
  end

  describe "compress" do
    setup [:setup_shell, :create_complete_snapshot]

    test "compresses snapshot and recomputes archive size", %{
      archive: archive,
      snapshot: snapshot,
      content: content
    } do
      original_size = byte_size(content)

      # Verify archive has the original size
      assert Repo.get(Archive, archive.id).total_size_bytes == original_size

      Mix.Tasks.Linkhut.Storage.run(["local.compress"])

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.encoding == "gzip"
      assert updated.original_file_size_bytes == original_size
      assert updated.file_size_bytes < original_size

      # Archive total_size_bytes should reflect the compressed size
      updated_archive = Repo.get(Archive, archive.id)
      assert updated_archive.total_size_bytes == updated.file_size_bytes
    end

    test "dry run does not modify files or DB", %{
      archive: archive,
      snapshot: snapshot,
      file_path: file_path,
      content: content
    } do
      Mix.Tasks.Linkhut.Storage.run(["local.compress", "--dry-run"])

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.encoding == nil
      assert updated.file_size_bytes == byte_size(content)
      assert File.read!(file_path) == content

      assert Repo.get(Archive, archive.id).total_size_bytes == byte_size(content)
    end
  end

  describe "decompress" do
    setup [:setup_shell, :create_complete_snapshot]

    test "decompresses snapshot and recomputes archive size", %{
      archive: archive,
      snapshot: snapshot,
      content: content
    } do
      original_size = byte_size(content)

      # First compress
      Mix.Tasks.Linkhut.Storage.run(["local.compress"])

      compressed_snapshot = Repo.get(Snapshot, snapshot.id)
      assert compressed_snapshot.encoding == "gzip"
      compressed_size = compressed_snapshot.file_size_bytes

      assert Repo.get(Archive, archive.id).total_size_bytes == compressed_size

      # Then decompress
      Mix.Tasks.Linkhut.Storage.run(["local.decompress"])

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.encoding == nil
      assert updated.file_size_bytes == original_size
      assert updated.original_file_size_bytes == nil

      # Archive should reflect the decompressed size
      updated_archive = Repo.get(Archive, archive.id)
      assert updated_archive.total_size_bytes == original_size

      # Original content should be restored
      {:ok, {:local, restored_path}} = StorageKey.parse(updated.storage_key)
      assert File.read!(restored_path) == content
    end

    test "dry run does not modify files or DB", %{
      archive: archive,
      snapshot: snapshot
    } do
      # First compress
      Mix.Tasks.Linkhut.Storage.run(["local.compress"])

      compressed_snapshot = Repo.get(Snapshot, snapshot.id)
      assert compressed_snapshot.encoding == "gzip"
      compressed_key = compressed_snapshot.storage_key
      compressed_size = compressed_snapshot.file_size_bytes

      # Dry run decompress
      Mix.Tasks.Linkhut.Storage.run(["local.decompress", "--dry-run"])

      # Nothing should have changed
      still_compressed = Repo.get(Snapshot, snapshot.id)
      assert still_compressed.encoding == "gzip"
      assert still_compressed.storage_key == compressed_key
      assert Repo.get(Archive, archive.id).total_size_bytes == compressed_size
    end
  end
end
