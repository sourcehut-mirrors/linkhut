defmodule Linkhut.Archiving.StorageKeyTest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.StorageKey

  describe "local/1" do
    test "produces correct prefixed string" do
      assert StorageKey.local("/data/archive/1/2/3.singlefile") ==
               "local:/data/archive/1/2/3.singlefile"
    end
  end

  describe "external/1" do
    test "produces correct prefixed string" do
      assert StorageKey.external("https://web.archive.org/web/123/https://example.com") ==
               "external:https://web.archive.org/web/123/https://example.com"
    end
  end

  describe "parse/1" do
    test "parses local key" do
      assert StorageKey.parse("local:/data/archive/1/2/3.singlefile") ==
               {:ok, {:local, "/data/archive/1/2/3.singlefile"}}
    end

    test "parses external key" do
      assert StorageKey.parse("external:https://web.archive.org/web/123/https://example.com") ==
               {:ok, {:external, "https://web.archive.org/web/123/https://example.com"}}
    end

    test "round-trips with local/1" do
      key = StorageKey.local("/some/path")
      assert {:ok, {:local, "/some/path"}} = StorageKey.parse(key)
    end

    test "round-trips with external/1" do
      key = StorageKey.external("https://example.com")
      assert {:ok, {:external, "https://example.com"}} = StorageKey.parse(key)
    end

    test "rejects unknown prefix" do
      assert StorageKey.parse("s3:bucket/key") == {:error, :invalid_storage_key}
    end

    test "rejects empty string" do
      assert StorageKey.parse("") == {:error, :invalid_storage_key}
    end

    test "handles empty path after local: prefix" do
      assert StorageKey.parse("local:") == {:ok, {:local, ""}}
    end

    test "handles empty url after external: prefix" do
      assert StorageKey.parse("external:") == {:ok, {:external, ""}}
    end
  end
end
