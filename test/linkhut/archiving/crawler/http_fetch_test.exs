defmodule Linkhut.Archiving.Crawler.HttpFetchTest do
  use ExUnit.Case, async: false

  alias Linkhut.Archiving.Crawler.HttpFetch
  alias Linkhut.Archiving.PreflightMeta

  describe "accepts/2" do
    test "accepts supported file types with the format they produce" do
      for {content_type, format} <- [
            {"application/pdf", "pdf"},
            {"text/plain", "text"},
            {"application/json", "json"},
            {"image/png", "image"}
          ] do
        assert HttpFetch.accepts("https://example.com/file", %PreflightMeta{
                 content_type: content_type,
                 status: 200
               }) == {:ok, format},
               "for #{content_type}"
      end
    end

    test "skips unsupported or missing content types" do
      for meta <- [
            %PreflightMeta{content_type: "text/html", status: 200},
            %PreflightMeta{content_type: "application/zip", status: 200},
            %PreflightMeta{content_type: nil, status: 200}
          ] do
        assert HttpFetch.accepts("https://example.com", meta) ==
                 {:reject, %{reason: :unsupported_format}},
               "for #{inspect(meta)}"
      end
    end

    test "skips when content_length exceeds max_bytes" do
      assert HttpFetch.accepts("https://example.com/doc.pdf", %PreflightMeta{
               content_type: "application/pdf",
               content_length: 100_000_000,
               status: 200
             }) == {:reject, %{reason: :file_too_large, content_length: 100_000_000}}
    end
  end

  describe "fetch/1" do
    test "downloads a file successfully" do
      for {content_type, body} <- [
            {"application/pdf", "%PDF-1.4 test pdf content"},
            {"application/json", ~s({"key": "value"})},
            {"text/plain", "Hello plain text!"}
          ] do
        Req.Test.stub(Linkhut.Links.Link, fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type(content_type)
          |> Plug.Conn.send_resp(200, body)
        end)

        assert {:ok, {:file, result}} =
                 HttpFetch.fetch("https://example.com/file", fetch_opts(content_type))

        assert result[:content_type] == content_type
        assert result[:response_code] == 200
        assert File.exists?(result[:path])

        content = File.read!(result[:path])
        assert content == body
      end
    end

    test "returns error for HTTP error status" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      assert {:error, error} =
               HttpFetch.fetch("https://example.com/missing.pdf", fetch_opts("application/pdf"))

      assert error.msg =~ "HTTP 404"
    end

    test "returns error when content verification fails" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/pdf")
        |> Plug.Conn.send_resp(200, "<html>not a PDF</html>")
      end)

      assert {:error, error} =
               HttpFetch.fetch("https://example.com/fake.pdf", fetch_opts("application/pdf"))

      assert error.msg =~ "content verification failed"
    end
  end

  # --- Helpers ---

  defp fetch_opts(content_type) do
    staging_dir =
      Path.join(System.tmp_dir!(), "httpfetch_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(staging_dir)
    on_exit(fn -> File.rm_rf(staging_dir) end)

    format = Linkhut.Archiving.MIME.format(content_type)
    [staging_dir: staging_dir, format: format]
  end
end
