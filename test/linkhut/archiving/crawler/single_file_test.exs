defmodule Linkhut.Archiving.Crawler.SingleFileTest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.Crawler.SingleFile

  describe "type/0" do
    test "returns 'singlefile'" do
      assert SingleFile.type() == "singlefile"
    end
  end

  describe "can_handle?/2" do
    test "returns true for text/html content type" do
      assert SingleFile.can_handle?("https://example.com", %{content_type: "text/html"})
    end

    test "returns false for application/pdf" do
      refute SingleFile.can_handle?("https://example.com/doc.pdf", %{
               content_type: "application/pdf"
             })
    end

    test "returns false for image/png" do
      refute SingleFile.can_handle?("https://example.com/image.png", %{
               content_type: "image/png"
             })
    end

    test "returns false for nil content type" do
      refute SingleFile.can_handle?("https://example.com", %{content_type: nil})
    end

    test "returns false for missing content type key" do
      refute SingleFile.can_handle?("https://example.com", %{})
    end
  end
end
