defmodule Linkhut.Archiving.MIMETest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.MIME

  describe "format_from_content_type/1" do
    test "maps known media types to their format" do
      assert MIME.format_from_content_type("text/html") == {:ok, "webpage"}
      assert MIME.format_from_content_type("application/pdf") == {:ok, "pdf"}
      assert MIME.format_from_content_type("text/plain") == {:ok, "text"}
      assert MIME.format_from_content_type("application/json") == {:ok, "json"}
      assert MIME.format_from_content_type("image/png") == {:ok, "image"}
    end

    test "maps unsupported but present media types to the catch-all format" do
      assert MIME.format_from_content_type("application/octet-stream") ==
               {:error, :unsupported_format}

      assert MIME.format_from_content_type("font/woff2") == {:error, :unsupported_format}
    end

    test "returns an error for a missing content type" do
      assert MIME.format_from_content_type(nil) == {:error, :unsupported_format}
    end
  end

  describe "formats/0" do
    test "lists the supported formats" do
      assert Enum.sort(MIME.formats()) ==
               Enum.sort(["webpage", "pdf", "text", "json", "image"])
    end
  end
end
