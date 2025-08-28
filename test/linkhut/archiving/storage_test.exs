defmodule Linkhut.Archiving.StorageTest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.Storage

  @data_dir Linkhut.Config.archiving(:data_dir)

  setup do
    File.rm_rf!(@data_dir)
    File.mkdir_p!(@data_dir)

    on_exit(fn -> File.rm_rf(@data_dir) end)

    :ok
  end

  describe "store/4" do
    test "delegates to the configured storage backend" do
      source = create_temp_file("test content")

      assert {:ok, "local:" <> _} = Storage.store({:file, source}, 1, 100, "singlefile")
    end
  end

  describe "resolve/1" do
    test "dispatches local: keys to Local module" do
      path = Path.join(@data_dir, "1/100/singlefile/12345/archive")
      key = "local:" <> path

      assert {:ok, {:file, ^path}} = Storage.resolve(key)
    end

    test "returns error for unknown key prefixes" do
      assert {:error, :invalid_storage_key} = Storage.resolve("s3:bucket/key")
    end

    test "returns error for empty key" do
      assert {:error, :invalid_storage_key} = Storage.resolve("")
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
