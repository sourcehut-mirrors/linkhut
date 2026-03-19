defmodule Linkhut.Archiving.Storage.S3Test do
  use ExUnit.Case, async: true

  import Linkhut.Config, only: [put_override: 3]

  alias Linkhut.Archiving.Snapshot
  alias Linkhut.Archiving.Storage.S3

  setup do
    put_override(S3, :bucket, "test-bucket")
    put_override(S3, :region, "eu-central-1")
    put_override(S3, :endpoint, "s3.example.com")
    put_override(S3, :access_key_id, "test-key")
    put_override(S3, :secret_access_key, "test-secret")
    put_override(S3, :scheme, "https://")
    put_override(S3, :port, 443)
    put_override(S3, :presign_ttl, 300)
    put_override(S3, :compression, :gzip)
    put_override(S3, :aws_module, __MODULE__.MockAws)
    :ok
  end

  describe "store/3" do
    test "stores data and returns s3:// storage key with correct structure" do
      snapshot = build_snapshot()

      assert {:ok, key, meta} =
               S3.store({:data, "hello"}, snapshot, content_type: "application/octet-stream")

      assert key == "s3://s3.example.com/test-bucket/1/100/42.webpage"
      assert meta.file_size_bytes == 5
      assert meta.encoding == nil
    end

    test "compresses compressible content" do
      data = String.duplicate("hello world ", 100)
      snapshot = build_snapshot()

      assert {:ok, key, meta} = S3.store({:data, data}, snapshot, content_type: "text/html")

      assert key =~ "42.webpage"
      refute key =~ ".gz"
      assert meta.encoding == "gzip"
      assert meta.file_size_bytes < byte_size(data)
    end

    test "skips compression for non-compressible types" do
      snapshot = build_snapshot()

      assert {:ok, key, meta} =
               S3.store({:data, "hello"}, snapshot, content_type: "image/png")

      assert key == "s3://s3.example.com/test-bucket/1/100/42.webpage"
      assert meta.encoding == nil
    end

    test "skips compression when compressed is larger" do
      # Small data where gzip overhead exceeds savings
      snapshot = build_snapshot()

      assert {:ok, key, meta} =
               S3.store({:data, "hi"}, snapshot, content_type: "text/html")

      refute key =~ ".gz"
      assert meta.encoding == nil
      assert meta.file_size_bytes == 2
    end

    test "skips compression when config is :none" do
      put_override(S3, :compression, :none)
      data = String.duplicate("hello world ", 100)
      snapshot = build_snapshot()

      assert {:ok, key, meta} = S3.store({:data, data}, snapshot, content_type: "text/html")

      refute key =~ ".gz"
      assert meta.encoding == nil
      assert meta.file_size_bytes == byte_size(data)
    end

    test "stores {:file, path} source" do
      path = create_temp_file("file content")
      snapshot = build_snapshot()

      assert {:ok, key, meta} =
               S3.store({:file, path}, snapshot, content_type: "application/octet-stream")

      assert key == "s3://s3.example.com/test-bucket/1/100/42.webpage"
      assert meta.file_size_bytes == byte_size("file content")
    end

    test "stores {:stream, stream} source" do
      stream = Stream.map(["chunk1", "chunk2"], & &1)
      snapshot = build_snapshot()

      assert {:ok, key, meta} =
               S3.store({:stream, stream}, snapshot, content_type: "application/octet-stream")

      assert key == "s3://s3.example.com/test-bucket/1/100/42.webpage"
      assert meta.file_size_bytes == byte_size("chunk1chunk2")
    end

    test "returns error on upload failure" do
      put_override(S3, :aws_module, __MODULE__.FailingMockAws)
      snapshot = build_snapshot()

      assert {:error, :upload_failed} =
               S3.store({:data, "hello"}, snapshot, content_type: "text/plain")
    end

    test "uses default endpoint from region when endpoint is not configured" do
      put_override(S3, :endpoint, nil)
      snapshot = build_snapshot()

      assert {:ok, key, _meta} =
               S3.store({:data, "hello"}, snapshot, content_type: "application/octet-stream")

      assert key =~ "s3://s3.eu-central-1.amazonaws.com/test-bucket/"
    end
  end

  describe "resolve/1" do
    test "generates presigned URL for active bucket key" do
      key = "s3://s3.example.com/test-bucket/1/100/42.webpage"
      assert {:ok, {:redirect, url}} = S3.resolve(key)
      assert url =~ "s3.example.com"
      assert url =~ "test-bucket"
      assert url =~ "1/100/42.webpage"
      assert url =~ "X-Amz-Expires=300"
    end

    test "resolves legacy bucket key" do
      put_override(S3, :legacy_buckets, [
        [
          endpoint: "old.s3.example.com",
          bucket: "old-bucket",
          region: "eu-west-1",
          access_key_id: "old-key",
          secret_access_key: "old-secret"
        ]
      ])

      key = "s3://old.s3.example.com/old-bucket/1/100/42.webpage"
      assert {:ok, {:redirect, url}} = S3.resolve(key)
      assert url =~ "old.s3.example.com"
      assert url =~ "old-bucket"
    end

    test "returns error for unknown endpoint+bucket" do
      key = "s3://unknown.example.com/unknown-bucket/1/100/42.webpage"
      assert {:error, :unknown_bucket} = S3.resolve(key)
    end

    test "returns error for invalid storage key" do
      assert {:error, :invalid_storage_key} = S3.resolve("local:/some/path")
    end
  end

  describe "resolve/2" do
    test "includes response-content-disposition in presigned URL" do
      key = "s3://s3.example.com/test-bucket/1/100/42.webpage"

      assert {:ok, {:redirect, url}} =
               S3.resolve(key, disposition: "attachment; filename=\"test.html\"")

      assert url =~ "response-content-disposition"
    end

    test "returns error for invalid storage key" do
      assert {:error, :invalid_storage_key} = S3.resolve("local:/some/path", [])
    end
  end

  describe "delete/1" do
    test "deletes object from active bucket" do
      key = "s3://s3.example.com/test-bucket/1/100/42.webpage"
      assert :ok = S3.delete(key)
    end

    test "returns error for unknown bucket" do
      key = "s3://unknown.example.com/unknown-bucket/1/100/42.webpage"
      assert {:error, :unknown_bucket} = S3.delete(key)
    end

    test "returns error for invalid key" do
      assert {:error, :invalid_storage_key} = S3.delete("local:/some/path")
    end
  end

  describe "storage_used/1" do
    test "sums object sizes from list response" do
      assert {:ok, 150} = S3.storage_used([])
    end

    test "returns error on network failure" do
      put_override(S3, :aws_module, __MODULE__.RaisingMockAws)
      assert {:error, _} = S3.storage_used([])
    end
  end

  defp build_snapshot(overrides \\ []) do
    defaults = [id: 42, user_id: 1, link_id: 100, format: "webpage", source: "singlefile"]
    struct!(Snapshot, Keyword.merge(defaults, overrides))
  end

  defp create_temp_file(content) do
    dir = Path.join(System.tmp_dir!(), "linkhut_s3_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "testfile")
    File.write!(path, content)
    path
  end

  defmodule MockAws do
    @moduledoc false
    def request(_operation, _config), do: {:ok, %{status_code: 200, body: ""}}
    def stream!(_operation, _config), do: [%{size: "100"}, %{size: "50"}]
  end

  defmodule FailingMockAws do
    @moduledoc false
    def request(_operation, _config), do: {:error, :upload_failed}
    def stream!(_operation, _config), do: []
  end

  defmodule RaisingMockAws do
    @moduledoc false
    def request(_operation, _config), do: {:ok, %{status_code: 200, body: ""}}
    def stream!(_operation, _config), do: raise("connection refused")
  end
end
