defmodule Linkhut.Archiving.PreflightMetaTest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.PreflightMeta

  describe "to_map/1" do
    test "returns nil for nil input" do
      assert PreflightMeta.to_map(nil) == nil
    end

    test "converts struct to string-keyed map" do
      meta = %PreflightMeta{
        scheme: "https",
        content_type: "text/html",
        content_length: 1234,
        final_url: "https://example.com",
        status: 200,
        method: "HEAD"
      }

      result = PreflightMeta.to_map(meta)

      assert result == %{
               "scheme" => "https",
               "content_type" => "text/html",
               "content_length" => 1234,
               "final_url" => "https://example.com",
               "status" => 200,
               "method" => "HEAD"
             }
    end
  end

  describe "from_map/1" do
    test "returns nil for nil input" do
      assert PreflightMeta.from_map(nil) == nil
    end

    test "reconstructs struct from string-keyed map" do
      map = %{
        "scheme" => "https",
        "content_type" => "text/html",
        "content_length" => 1234,
        "final_url" => "https://example.com",
        "status" => 200
      }

      result = PreflightMeta.from_map(map)

      assert %PreflightMeta{} = result
      assert result.scheme == "https"
      assert result.content_type == "text/html"
      assert result.content_length == 1234
      assert result.final_url == "https://example.com"
      assert result.status == 200
    end

    test "handles partial map with missing keys" do
      map = %{"scheme" => "https", "status" => 200}

      result = PreflightMeta.from_map(map)

      assert result.scheme == "https"
      assert result.status == 200
      assert result.content_type == nil
      assert result.content_length == nil
      assert result.final_url == nil
    end

    test "discards unknown keys" do
      map = %{
        "scheme" => "https",
        "status" => 200,
        "unknown_key" => "should be ignored",
        "another" => 42
      }

      result = PreflightMeta.from_map(map)

      assert result.scheme == "https"
      assert result.status == 200
    end
  end

  describe "roundtrip" do
    test "struct -> to_map -> from_map produces equal struct" do
      original = %PreflightMeta{
        scheme: "https",
        content_type: "application/pdf",
        content_length: 5678,
        final_url: "https://example.com/doc.pdf",
        status: 200,
        method: "HEAD"
      }

      assert original == original |> PreflightMeta.to_map() |> PreflightMeta.from_map()
    end

    test "struct with nil fields roundtrips correctly" do
      original = %PreflightMeta{scheme: "https", status: 500}

      assert original == original |> PreflightMeta.to_map() |> PreflightMeta.from_map()
    end
  end

  describe "pattern matching" do
    test "struct works with map pattern matching" do
      meta = %PreflightMeta{content_type: "text/html", status: 200}

      assert %{content_type: "text/html", status: 200} = meta
    end

    test "struct works with struct pattern in function heads" do
      meta = %PreflightMeta{content_type: "text/html", status: 200}

      assert match?(%{content_type: "text/html", status: s} when s < 400, meta)
    end
  end
end
