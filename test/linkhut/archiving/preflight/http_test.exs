defmodule Linkhut.Archiving.Preflight.HTTPTest do
  use ExUnit.Case, async: false

  alias Linkhut.Archiving.Preflight
  alias Linkhut.Archiving.PreflightMeta

  describe "execute/1" do
    test "returns PreflightMeta with correct fields on success" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html; charset=utf-8")
        |> Plug.Conn.put_resp_header("content-length", "1234")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, %PreflightMeta{} = meta} =
               Preflight.HTTP.execute("https://example.com/page")

      assert meta.scheme == "https"
      assert meta.content_type == "text/html"
      assert meta.content_length == 1234
      assert meta.status == 200
      assert meta.final_url =~ "example.com"
    end

    test "normalizes content-type by stripping charset and lowercasing" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header(
          "content-type",
          "Text/HTML; charset=UTF-8; boundary=something"
        )
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, meta} = Preflight.HTTP.execute("https://example.com")
      assert meta.content_type == "text/html"
    end

    test "parses content-length as integer" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/pdf")
        |> Plug.Conn.put_resp_header("content-length", "99999")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, meta} = Preflight.HTTP.execute("https://example.com/doc.pdf")
      assert meta.content_length == 99_999
    end

    test "returns nil content_length when header is missing" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, meta} = Preflight.HTTP.execute("https://example.com")
      assert meta.content_length == nil
    end

    test "returns nil content_length for invalid value" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html")
        |> Plug.Conn.put_resp_header("content-length", "not-a-number")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, meta} = Preflight.HTTP.execute("https://example.com")
      assert meta.content_length == nil
    end

    test "captures final URL after redirect" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        case conn.request_path do
          "/page" ->
            conn
            |> Plug.Conn.put_resp_header("location", "/final-page")
            |> Plug.Conn.send_resp(301, "")

          "/final-page" ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "text/html")
            |> Plug.Conn.send_resp(200, "")
        end
      end)

      assert {:ok, meta} = Preflight.HTTP.execute("https://example.com/page")
      assert meta.final_url =~ "/final-page"
      assert meta.status == 200
    end

    test "HTTP error status codes are still {:ok, meta}" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      assert {:ok, meta} = Preflight.HTTP.execute("https://example.com/missing")
      assert meta.status == 404
    end

    test "transport failure returns {:error, reason}" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, _reason} = Preflight.HTTP.execute("https://example.com")
    end

    test "returns nil content_type when header is missing" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, meta} = Preflight.HTTP.execute("https://example.com")
      assert meta.content_type == nil
    end
  end
end
