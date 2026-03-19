defmodule Linkhut.Archiving.StorageTest do
  use ExUnit.Case, async: true

  import Linkhut.Config, only: [put_override: 3]

  alias Linkhut.Archiving.{Snapshot, Storage}
  alias Linkhut.Archiving.Storage.S3

  @data_dir Linkhut.Config.archiving(:data_dir)

  setup do
    File.rm_rf!(@data_dir)
    File.mkdir_p!(@data_dir)

    on_exit(fn -> File.rm_rf(@data_dir) end)

    :ok
  end

  describe "store/3" do
    test "delegates to the configured storage backend" do
      source = create_temp_file("test content")

      snapshot =
        build_snapshot(id: 1, user_id: 1, link_id: 100, format: "webpage", source: "singlefile")

      assert {:ok, "local:" <> _, _meta} = Storage.store({:file, source}, snapshot)
    end
  end

  describe "resolve/1" do
    test "dispatches local: keys to Local module" do
      path = Path.join(@data_dir, "1/100/singlefile/12345/archive")
      key = "local:" <> path

      assert {:ok, {:file, ^path}} = Storage.resolve(key)
    end

    test "dispatches s3:// keys to S3 module" do
      setup_s3_config()
      key = "s3://s3.example.com/test-bucket/1/100/42.webpage"
      assert {:ok, {:redirect, url}} = Storage.resolve(key)
      assert url =~ "s3.example.com"
    end

    test "returns error for unknown key prefixes" do
      assert {:error, :invalid_storage_key} = Storage.resolve("cloud:bucket/key")
    end

    test "returns error for empty key" do
      assert {:error, :invalid_storage_key} = Storage.resolve("")
    end
  end

  describe "resolve/2" do
    test "dispatches s3:// keys to S3 module with opts" do
      setup_s3_config()
      key = "s3://s3.example.com/test-bucket/1/100/42.webpage"

      assert {:ok, {:redirect, url}} =
               Storage.resolve(key, disposition: "attachment; filename=\"test.html\"")

      assert url =~ "response-content-disposition"
    end

    test "falls back to resolve/1 for non-S3 keys" do
      path = Path.join(@data_dir, "1/100/42.webpage")
      key = "local:" <> path

      assert {:ok, {:file, ^path}} = Storage.resolve(key, disposition: "attachment")
    end
  end

  describe "delete/1" do
    test "dispatches s3:// keys to S3 module" do
      setup_s3_config()
      key = "s3://s3.example.com/test-bucket/1/100/42.webpage"
      assert :ok = Storage.delete(key)
    end

    test "returns :ok for external: keys" do
      assert :ok = Storage.delete("external:https://example.com/archive")
    end

    test "returns error for unknown key prefixes" do
      assert {:error, :invalid_storage_key} = Storage.delete("cloud:bucket/key")
    end
  end

  defmodule MockAws do
    @moduledoc false
    def request(_operation, _config), do: {:ok, %{status_code: 200, body: ""}}
    def stream!(_operation, _config), do: [%{size: "100"}, %{size: "50"}]
  end

  defp setup_s3_config do
    put_override(S3, :bucket, "test-bucket")
    put_override(S3, :region, "eu-central-1")
    put_override(S3, :endpoint, "s3.example.com")
    put_override(S3, :access_key_id, "test-key")
    put_override(S3, :secret_access_key, "test-secret")
    put_override(S3, :scheme, "https://")
    put_override(S3, :port, 443)
    put_override(S3, :presign_ttl, 300)
    put_override(S3, :aws_module, MockAws)
  end

  defp build_snapshot(attrs) do
    struct!(Snapshot, Enum.into(attrs, %{}))
  end

  defp create_temp_file(content) do
    dir = Path.join(System.tmp_dir!(), "linkhut_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "testfile")
    File.write!(path, content)
    path
  end
end
