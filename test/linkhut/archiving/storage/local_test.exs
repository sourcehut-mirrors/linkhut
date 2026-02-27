defmodule Linkhut.Archiving.Storage.LocalTest do
  use ExUnit.Case, async: false

  alias Linkhut.Archiving.Snapshot
  alias Linkhut.Archiving.Storage.Local

  @data_dir Linkhut.Config.archiving(:data_dir)

  setup do
    # Ensure clean data_dir for each test
    File.rm_rf!(@data_dir)
    File.mkdir_p!(@data_dir)

    on_exit(fn -> File.rm_rf(@data_dir) end)

    :ok
  end

  defp build_snapshot(overrides \\ []) do
    defaults = [id: 1, user_id: 42, link_id: 999, archive_id: 10, type: "singlefile"]
    struct!(Snapshot, Keyword.merge(defaults, overrides))
  end

  describe "store/2 with {:file, path}" do
    test "stores a file and returns a local: storage key" do
      source = create_temp_file("hello world")
      snapshot = build_snapshot()

      assert {:ok, "local:" <> dest} = Local.store({:file, source}, snapshot)
      assert String.starts_with?(dest, @data_dir)
      assert File.exists?(dest)
      assert File.read!(dest) == "hello world"
    end

    test "removes the source file after storing" do
      source = create_temp_file("test content")
      snapshot = build_snapshot()

      assert {:ok, _key} = Local.store({:file, source}, snapshot)
      refute File.exists?(source)
    end

    test "builds path with user_id/link_id/archive_id/snapshot_id.type structure" do
      source = create_temp_file("test")

      snapshot =
        build_snapshot(id: 1, user_id: 42, link_id: 999, archive_id: 10, type: "singlefile")

      assert {:ok, "local:" <> dest} = Local.store({:file, source}, snapshot)
      assert dest =~ "/42/999/10/1.singlefile"
    end
  end

  describe "store/2 with {:data, binary}" do
    test "stores binary data and returns a local: storage key" do
      snapshot = build_snapshot()

      assert {:ok, "local:" <> dest} =
               Local.store({:data, "binary content"}, snapshot)

      assert File.exists?(dest)
      assert File.read!(dest) == "binary content"
    end
  end

  describe "store/2 with {:stream, enumerable}" do
    test "stores streamed data and returns a local: storage key" do
      stream = Stream.map(["chunk1", "chunk2", "chunk3"], & &1)
      snapshot = build_snapshot()

      assert {:ok, "local:" <> dest} = Local.store({:stream, stream}, snapshot)
      assert File.exists?(dest)
      assert File.read!(dest) == "chunk1chunk2chunk3"
    end
  end

  describe "resolve/1" do
    test "resolves a valid local: key to {:file, path}" do
      path = Path.join(@data_dir, "1/100/singlefile/12345/archive")
      key = "local:" <> path

      assert {:ok, {:file, ^path}} = Local.resolve(key)
    end

    test "rejects path traversal attempts" do
      evil_path = Path.join(@data_dir, "../../../etc/passwd")
      key = "local:" <> evil_path

      assert {:error, :invalid_storage_key} = Local.resolve(key)
    end

    test "rejects paths outside data_dir" do
      key = "local:/etc/passwd"

      assert {:error, :invalid_storage_key} = Local.resolve(key)
    end

    test "rejects non-local: prefixed keys" do
      assert {:error, :invalid_storage_key} = Local.resolve("cloud:bucket/key")
    end
  end

  describe "delete/1" do
    test "deletes an existing file and returns :ok" do
      path = Path.join(@data_dir, "1/100/10/42.singlefile")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "content")

      assert :ok = Local.delete("local:" <> path)
      refute File.exists?(path)
    end

    test "returns :ok for non-existent file (idempotent)" do
      path = Path.join(@data_dir, "1/100/10/missing.singlefile")
      assert :ok = Local.delete("local:" <> path)
    end

    test "rejects path traversal" do
      evil_path = Path.join(@data_dir, "../../../etc/passwd")
      assert {:error, :invalid_storage_key} = Local.delete("local:" <> evil_path)
    end

    test "prunes empty parent directories after deletion" do
      path = Path.join(@data_dir, "1/100/10/42.singlefile")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "content")

      assert :ok = Local.delete("local:" <> path)

      refute File.exists?(Path.join(@data_dir, "1/100/10"))
      refute File.exists?(Path.join(@data_dir, "1/100"))
      refute File.exists?(Path.join(@data_dir, "1"))
      # data_dir itself must remain
      assert File.exists?(@data_dir)
    end

    test "stops pruning at first non-empty parent" do
      # Create two files in sibling directories
      path1 = Path.join(@data_dir, "1/100/10/42.singlefile")
      path2 = Path.join(@data_dir, "1/100/20/43.singlefile")
      File.mkdir_p!(Path.dirname(path1))
      File.mkdir_p!(Path.dirname(path2))
      File.write!(path1, "content1")
      File.write!(path2, "content2")

      assert :ok = Local.delete("local:" <> path1)

      # archive_id dir should be pruned
      refute File.exists?(Path.join(@data_dir, "1/100/10"))
      # link_id dir should remain (still has sibling)
      assert File.exists?(Path.join(@data_dir, "1/100"))
      assert File.exists?(Path.join(@data_dir, "1"))
    end
  end

  describe "storage_used/1" do
    test "returns 0 for empty data dir" do
      assert {:ok, 0} = Local.storage_used([])
    end

    test "returns total size of all files" do
      File.mkdir_p!(Path.join(@data_dir, "1/100/10"))
      File.write!(Path.join(@data_dir, "1/100/10/42.singlefile"), "hello")
      File.mkdir_p!(Path.join(@data_dir, "2/200/20"))
      File.write!(Path.join(@data_dir, "2/200/20/43.singlefile"), "world!!")

      assert {:ok, size} = Local.storage_used([])
      assert size == 12
    end

    test "with user_id returns size of that user's files only" do
      File.mkdir_p!(Path.join(@data_dir, "1/100/10"))
      File.write!(Path.join(@data_dir, "1/100/10/42.singlefile"), "hello")
      File.mkdir_p!(Path.join(@data_dir, "2/200/20"))
      File.write!(Path.join(@data_dir, "2/200/20/43.singlefile"), "world!!")

      assert {:ok, 5} = Local.storage_used(user_id: 1)
      assert {:ok, 7} = Local.storage_used(user_id: 2)
    end

    test "with non-existent user_id returns 0" do
      assert {:ok, 0} = Local.storage_used(user_id: 999)
    end

    test "with link_id scopes to user/link directory" do
      File.mkdir_p!(Path.join(@data_dir, "1/100/10"))
      File.write!(Path.join(@data_dir, "1/100/10/42.singlefile"), "hello")
      File.mkdir_p!(Path.join(@data_dir, "1/200/20"))
      File.write!(Path.join(@data_dir, "1/200/20/43.singlefile"), "world!!")

      assert {:ok, 5} = Local.storage_used(user_id: 1, link_id: 100)
      assert {:ok, 7} = Local.storage_used(user_id: 1, link_id: 200)
    end

    test "with archive_id scopes to user/link/archive directory" do
      File.mkdir_p!(Path.join(@data_dir, "1/100/10"))
      File.write!(Path.join(@data_dir, "1/100/10/42.singlefile"), "hello")
      File.mkdir_p!(Path.join(@data_dir, "1/100/20"))
      File.write!(Path.join(@data_dir, "1/100/20/43.singlefile"), "world!!")

      assert {:ok, 5} = Local.storage_used(user_id: 1, link_id: 100, archive_id: 10)
      assert {:ok, 7} = Local.storage_used(user_id: 1, link_id: 100, archive_id: 20)
    end
  end

  describe "legacy_data_dirs" do
    @legacy_dir Path.join(System.tmp_dir!(), "linkhut_test_legacy_archives")

    setup do
      File.mkdir_p!(@legacy_dir)

      archiving = Application.get_env(:linkhut, Linkhut)[:archiving]
      updated = Keyword.put(archiving, :legacy_data_dirs, [@legacy_dir])

      Application.put_env(
        :linkhut,
        Linkhut,
        Keyword.put(Application.get_env(:linkhut, Linkhut), :archiving, updated)
      )

      on_exit(fn ->
        File.rm_rf(@legacy_dir)

        restored = Keyword.delete(archiving, :legacy_data_dirs)

        Application.put_env(
          :linkhut,
          Linkhut,
          Keyword.put(Application.get_env(:linkhut, Linkhut), :archiving, restored)
        )
      end)

      :ok
    end

    test "resolve/1 accepts paths in a legacy data dir" do
      path = Path.join(@legacy_dir, "1/100/singlefile/12345/archive")

      assert {:ok, {:file, ^path}} = Local.resolve("local:" <> path)
    end

    test "delete/1 accepts paths in a legacy data dir" do
      path = Path.join(@legacy_dir, "1/100/singlefile/12345/archive")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "old content")

      assert :ok = Local.delete("local:" <> path)
      refute File.exists?(path)
    end

    test "resolve/1 still rejects paths outside all allowed dirs" do
      assert {:error, :invalid_storage_key} = Local.resolve("local:/etc/passwd")
    end
  end

  defp create_temp_file(content) do
    dir = Path.join(System.tmp_dir!(), "linkhut_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "testfile")
    File.write!(path, content)
    path
  end
end
