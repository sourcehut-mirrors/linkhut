defmodule Mix.Tasks.Linkhut.StorageTest do
  use Linkhut.DataCase, async: false

  import Linkhut.Factory

  alias Linkhut.Archiving.{Snapshot, StorageKey}

  @moduletag :mix_task

  @data_dir Linkhut.Config.archiving(:data_dir)

  defp setup_shell(_context) do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp create_complete_snapshot(_context) do
    content = "<html><body>#{String.duplicate("test content ", 100)}</body></html>"

    File.rm_rf!(@data_dir)
    File.mkdir_p!(@data_dir)
    file_path = Path.join(@data_dir, "snapshot_file")
    File.write!(file_path, content)

    snapshot =
      insert(:snapshot,
        storage_key: StorageKey.local(file_path),
        file_size_bytes: byte_size(content),
        archive_metadata: %{"content_type" => "text/html"}
      )

    on_exit(fn -> File.rm_rf(@data_dir) end)

    %{snapshot: snapshot, content: content, file_path: file_path}
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

    test "compresses snapshot", %{snapshot: snapshot, content: content} do
      original_size = byte_size(content)

      Mix.Tasks.Linkhut.Storage.run(["local.compress"])

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.encoding == "gzip"
      assert updated.original_file_size_bytes == original_size
      assert updated.file_size_bytes < original_size
    end

    test "dry run does not modify files or DB", %{
      snapshot: snapshot,
      file_path: file_path,
      content: content
    } do
      Mix.Tasks.Linkhut.Storage.run(["local.compress", "--dry-run"])

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.encoding == nil
      assert updated.file_size_bytes == byte_size(content)
      assert File.read!(file_path) == content
    end
  end

  describe "decompress" do
    setup [:setup_shell, :create_complete_snapshot]

    test "decompresses snapshot", %{snapshot: snapshot, content: content} do
      original_size = byte_size(content)

      # First compress
      Mix.Tasks.Linkhut.Storage.run(["local.compress"])

      compressed_snapshot = Repo.get(Snapshot, snapshot.id)
      assert compressed_snapshot.encoding == "gzip"

      # Then decompress
      Mix.Tasks.Linkhut.Storage.run(["local.decompress"])

      updated = Repo.get(Snapshot, snapshot.id)
      assert updated.encoding == nil
      assert updated.file_size_bytes == original_size
      assert updated.original_file_size_bytes == nil

      # Original content should be restored
      {:ok, {:local, restored_path}} = StorageKey.parse(updated.storage_key)
      assert File.read!(restored_path) == content
    end
  end
end
