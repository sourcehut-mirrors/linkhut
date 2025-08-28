defmodule Linkhut.Archiving.Storage.LocalTest do
  use ExUnit.Case, async: true

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
      assert {:ok, "local:" <> dest} = Local.store({:data, "binary content"}, 1, 100, "singlefile")
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
      assert {:error, :invalid_storage_key} = Local.resolve("s3:bucket/key")
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
