defmodule Linkhut.Archiving.Storage.LocalTest do
  use ExUnit.Case, async: false

  alias Linkhut.Archiving.Storage.Local

  @data_dir Linkhut.Config.archiving(:data_dir)

  setup do
    # Ensure clean data_dir for each test
    File.rm_rf!(@data_dir)
    File.mkdir_p!(@data_dir)

    on_exit(fn -> File.rm_rf(@data_dir) end)

    :ok
  end

  describe "store/4 with {:file, path}" do
    test "stores a file and returns a local: storage key" do
      source = create_temp_file("hello world")

      assert {:ok, "local:" <> dest} = Local.store({:file, source}, 1, 100, "singlefile")
      assert String.starts_with?(dest, @data_dir)
      assert File.exists?(dest)
      assert File.read!(dest) == "hello world"
    end

    test "removes the source file after storing" do
      source = create_temp_file("test content")

      assert {:ok, _key} = Local.store({:file, source}, 1, 100, "singlefile")
      refute File.exists?(source)
    end

    test "builds path with user_id/link_id/type structure" do
      source = create_temp_file("test")

      assert {:ok, "local:" <> dest} = Local.store({:file, source}, 42, 999, "singlefile")
      assert dest =~ "/42/999/singlefile/"
    end
  end

  describe "store/4 with {:data, binary}" do
    test "stores binary data and returns a local: storage key" do
      assert {:ok, "local:" <> dest} =
               Local.store({:data, "binary content"}, 1, 100, "singlefile")

      assert File.exists?(dest)
      assert File.read!(dest) == "binary content"
    end
  end

  describe "store/4 with {:stream, enumerable}" do
    test "stores streamed data and returns a local: storage key" do
      stream = Stream.map(["chunk1", "chunk2", "chunk3"], & &1)

      assert {:ok, "local:" <> dest} = Local.store({:stream, stream}, 1, 100, "singlefile")
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
      path = Path.join(@data_dir, "1/100/singlefile/12345/archive")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "content")

      assert :ok = Local.delete("local:" <> path)
      refute File.exists?(path)
    end

    test "returns :ok for non-existent file (idempotent)" do
      path = Path.join(@data_dir, "1/100/singlefile/12345/missing")
      assert :ok = Local.delete("local:" <> path)
    end

    test "rejects path traversal" do
      evil_path = Path.join(@data_dir, "../../../etc/passwd")
      assert {:error, :invalid_storage_key} = Local.delete("local:" <> evil_path)
    end
  end

  describe "storage_used/1" do
    test "returns 0 for empty data dir" do
      assert {:ok, 0} = Local.storage_used([])
    end

    test "returns total size of all files" do
      File.mkdir_p!(Path.join(@data_dir, "1/100/singlefile/12345"))
      File.write!(Path.join(@data_dir, "1/100/singlefile/12345/archive"), "hello")
      File.mkdir_p!(Path.join(@data_dir, "2/200/singlefile/12345"))
      File.write!(Path.join(@data_dir, "2/200/singlefile/12345/archive"), "world!!")

      assert {:ok, size} = Local.storage_used([])
      assert size == 12
    end

    test "with user_id returns size of that user's files only" do
      File.mkdir_p!(Path.join(@data_dir, "1/100/singlefile/12345"))
      File.write!(Path.join(@data_dir, "1/100/singlefile/12345/archive"), "hello")
      File.mkdir_p!(Path.join(@data_dir, "2/200/singlefile/12345"))
      File.write!(Path.join(@data_dir, "2/200/singlefile/12345/archive"), "world!!")

      assert {:ok, 5} = Local.storage_used(user_id: 1)
      assert {:ok, 7} = Local.storage_used(user_id: 2)
    end

    test "with non-existent user_id returns 0" do
      assert {:ok, 0} = Local.storage_used(user_id: 999)
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
