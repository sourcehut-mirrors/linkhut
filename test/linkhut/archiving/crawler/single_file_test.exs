defmodule Linkhut.Archiving.Crawler.SingleFileTest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.Crawler.SingleFile

  describe "source_type/0" do
    test "returns 'singlefile'" do
      assert SingleFile.source_type() == "singlefile"
    end
  end

  describe "fetch/1" do
    test "returns {:error, ...} when SingleFile binary is missing" do
      Application.put_env(:single_file, :path, "/nonexistent/single-file")

      try do
        context = %Linkhut.Archiving.Crawler.Context{
          user_id: 1,
          link_id: 1,
          url: "https://example.com",
          snapshot_id: 1
        }

        assert {:error, %{msg: reason}} = SingleFile.fetch(context)
        assert is_binary(reason)
      after
        Application.delete_env(:single_file, :path)
      end
    end
  end

  describe "can_handle?/2" do
    test "returns true for text/html content type" do
      assert SingleFile.can_handle?("https://example.com", %{
               content_type: "text/html",
               status: 200
             })
    end

    test "returns true for application/xhtml+xml content type" do
      assert SingleFile.can_handle?("https://example.com", %{
               content_type: "application/xhtml+xml",
               status: 200
             })
    end

    test "returns false for error status codes" do
      refute SingleFile.can_handle?("https://example.com", %{
               content_type: "text/html",
               status: 404
             })

      refute SingleFile.can_handle?("https://example.com", %{
               content_type: "text/html",
               status: 500
             })
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
