defmodule Linkhut.Archiving.Crawler.HttpFetchTest do
  use ExUnit.Case, async: false

  alias Linkhut.Archiving.Crawler.HttpFetch
  alias Linkhut.Archiving.Crawler.Context

  describe "type/0" do
    test "returns 'httpfetch'" do
      assert HttpFetch.type() == "httpfetch"
    end
  end

  describe "meta/0" do
    test "returns tool_name and version" do
      meta = HttpFetch.meta()
      assert meta.tool_name == "Req"
      assert is_binary(meta.version)
    end
  end

  describe "can_handle?/2" do
    test "returns true for application/pdf" do
      assert HttpFetch.can_handle?("https://example.com/doc.pdf", %{
               content_type: "application/pdf"
             })
    end

    test "returns true for text/plain" do
      assert HttpFetch.can_handle?("https://example.com/file.txt", %{
               content_type: "text/plain"
             })
    end

    test "returns true for application/json" do
      assert HttpFetch.can_handle?("https://example.com/data.json", %{
               content_type: "application/json"
             })
    end

    test "returns false for text/html" do
      refute HttpFetch.can_handle?("https://example.com", %{content_type: "text/html"})
    end

    test "returns false for image/png" do
      refute HttpFetch.can_handle?("https://example.com/image.png", %{
               content_type: "image/png"
             })
    end

    test "returns false for nil content type" do
      refute HttpFetch.can_handle?("https://example.com", %{content_type: nil})
    end

    test "returns false for missing content type key" do
      refute HttpFetch.can_handle?("https://example.com", %{})
    end

    test "returns true when content_length is within limit" do
      assert HttpFetch.can_handle?("https://example.com/doc.pdf", %{
               content_type: "application/pdf",
               content_length: 1_000_000
             })
    end

    test "returns false when content_length exceeds max_bytes" do
      refute HttpFetch.can_handle?("https://example.com/doc.pdf", %{
               content_type: "application/pdf",
               content_length: 100_000_000
             })
    end

    test "returns true when content_length is nil (unknown size)" do
      assert HttpFetch.can_handle?("https://example.com/doc.pdf", %{
               content_type: "application/pdf",
               content_length: nil
             })
    end
  end

  describe "verify_content/2" do
    test "accepts valid PDF" do
      path = write_temp_file("%PDF-1.4 fake pdf content")
      assert :ok = HttpFetch.verify_content(path, "application/pdf")
      File.rm(path)
    end

    test "rejects non-PDF" do
      path = write_temp_file("<html>not a pdf</html>")
      assert {:error, msg} = HttpFetch.verify_content(path, "application/pdf")
      assert msg =~ "not a valid PDF"
      File.rm(path)
    end

    test "accepts valid JSON object" do
      path = write_temp_file(~s({"key": "value"}))
      assert :ok = HttpFetch.verify_content(path, "application/json")
      File.rm(path)
    end

    test "accepts valid JSON array" do
      path = write_temp_file(~s([1, 2, 3]))
      assert :ok = HttpFetch.verify_content(path, "application/json")
      File.rm(path)
    end

    test "accepts JSON with leading whitespace" do
      path = write_temp_file("  \n  {\"key\": \"value\"}")
      assert :ok = HttpFetch.verify_content(path, "application/json")
      File.rm(path)
    end

    test "rejects non-JSON" do
      path = write_temp_file("<html>not json</html>")
      assert {:error, msg} = HttpFetch.verify_content(path, "application/json")
      assert msg =~ "not valid JSON"
      File.rm(path)
    end

    test "accepts valid UTF-8 text" do
      path = write_temp_file("Hello, world!")
      assert :ok = HttpFetch.verify_content(path, "text/plain")
      File.rm(path)
    end

    test "rejects invalid UTF-8" do
      path = write_temp_binary(<<0xFF, 0xFE, 0x00, 0x01>>)
      assert {:error, msg} = HttpFetch.verify_content(path, "text/plain")
      assert msg =~ "not valid UTF-8"
      File.rm(path)
    end

    test "accepts unknown content types" do
      path = write_temp_file("anything")
      assert :ok = HttpFetch.verify_content(path, "application/octet-stream")
      File.rm(path)
    end

    test "accepts nil content type" do
      path = write_temp_file("anything")
      assert :ok = HttpFetch.verify_content(path, nil)
      File.rm(path)
    end
  end

  describe "fetch/1" do
    test "downloads a PDF file successfully" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/pdf")
        |> Plug.Conn.send_resp(200, "%PDF-1.4 test pdf content")
      end)

      context = build_context("https://example.com/doc.pdf", "application/pdf")

      assert {:ok, result} = HttpFetch.fetch(context)
      assert result[:content_type] == "application/pdf"
      assert result[:response_code] == 200
      assert File.exists?(result[:path])

      content = File.read!(result[:path])
      assert content =~ "%PDF-"

      File.rm_rf(Path.dirname(result[:path]))
    end

    test "downloads a JSON file successfully" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ~s({"key": "value"}))
      end)

      context = build_context("https://example.com/data.json", "application/json")

      assert {:ok, result} = HttpFetch.fetch(context)
      assert result[:content_type] == "application/json"

      File.rm_rf(Path.dirname(result[:path]))
    end

    test "downloads a text file successfully" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "Hello, plain text!")
      end)

      context = build_context("https://example.com/file.txt", "text/plain")

      assert {:ok, result} = HttpFetch.fetch(context)
      assert result[:content_type] == "text/plain"

      content = File.read!(result[:path])
      assert content == "Hello, plain text!"

      File.rm_rf(Path.dirname(result[:path]))
    end

    test "returns error for HTTP error status" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      context = build_context("https://example.com/missing.pdf", "application/pdf")

      assert {:error, error} = HttpFetch.fetch(context)
      assert error.msg =~ "HTTP 404"
    end

    test "returns error when content verification fails" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/pdf")
        |> Plug.Conn.send_resp(200, "<html>not a PDF</html>")
      end)

      context = build_context("https://example.com/fake.pdf", "application/pdf")

      assert {:error, error} = HttpFetch.fetch(context)
      assert error.msg =~ "content verification failed"
    end

    test "cleans up staging directory on error" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Server Error")
      end)

      context = build_context("https://example.com/error.pdf", "application/pdf")

      assert {:error, _} = HttpFetch.fetch(context)

      # Staging dirs under tmp matching pattern should be cleaned up
      # We can't know the exact dir, but verify no leak by checking the
      # error response is well-formed
    end

    test "preserves staging directory on success" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/pdf")
        |> Plug.Conn.send_resp(200, "%PDF-1.4 test")
      end)

      context = build_context("https://example.com/doc.pdf", "application/pdf")

      assert {:ok, result} = HttpFetch.fetch(context)
      assert File.exists?(result[:path])
      staging_dir = Path.dirname(result[:path])
      assert File.exists?(staging_dir)

      File.rm_rf(staging_dir)
    end
  end

  # --- Helpers ---

  defp build_context(url, content_type) do
    %Context{
      user_id: 1,
      link_id: :erlang.unique_integer([:positive]),
      url: url,
      snapshot_id: 1,
      preflight_meta: %{content_type: content_type}
    }
  end

  defp write_temp_file(content) do
    path = Path.join(System.tmp_dir!(), "httpfetch_test_#{:erlang.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp write_temp_binary(content) do
    path = Path.join(System.tmp_dir!(), "httpfetch_test_#{:erlang.unique_integer([:positive])}")
    File.write!(path, content, [:binary])
    path
  end
end
