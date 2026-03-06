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

      assert {:ok, %PreflightMeta{} = meta, []} =
               Preflight.HTTP.execute("https://example.com/page")

      assert meta.scheme == "https"
      assert meta.content_type == "text/html"
      assert meta.content_length == 1234
      assert meta.status == 200
      assert meta.method == "HEAD"
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

      assert {:ok, meta, _events} = Preflight.HTTP.execute("https://example.com")
      assert meta.content_type == "text/html"
    end

    test "parses content-length as integer" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/pdf")
        |> Plug.Conn.put_resp_header("content-length", "99999")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, meta, _events} = Preflight.HTTP.execute("https://example.com/doc.pdf")
      assert meta.content_length == 99_999
    end

    test "returns nil content_length when header is missing" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, meta, _events} = Preflight.HTTP.execute("https://example.com")
      assert meta.content_length == nil
    end

    test "returns nil content_length for invalid value" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html")
        |> Plug.Conn.put_resp_header("content-length", "not-a-number")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, meta, _events} = Preflight.HTTP.execute("https://example.com")
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

      assert {:ok, meta, _events} = Preflight.HTTP.execute("https://example.com/page")
      assert meta.final_url =~ "/final-page"
      assert meta.status == 200
    end

    test "HTTP error status codes are still {:ok, meta, events}" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      assert {:ok, meta, _events} = Preflight.HTTP.execute("https://example.com/missing")
      assert meta.status == 404
    end

    test "falls back to GET on 405 and returns metadata from GET response" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        case conn.method do
          "HEAD" ->
            Plug.Conn.send_resp(conn, 405, "Method Not Allowed")

          "GET" ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "text/html; charset=utf-8")
            |> Plug.Conn.put_resp_header("content-length", "5000")
            |> Plug.Conn.send_resp(200, "<html>body</html>")
        end
      end)

      assert {:ok, meta, events} = Preflight.HTTP.execute("https://example.com/page")
      assert meta.status == 200
      assert meta.content_type == "text/html"
      assert meta.content_length == 5000
      assert meta.method == "GET"

      assert [{"preflight_fallback", %{"msg" => "preflight_head_failed", "status" => 405}}] =
               events
    end

    test "GET fallback follows redirects" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        case {conn.method, conn.request_path} do
          {"HEAD", _} ->
            Plug.Conn.send_resp(conn, 405, "Method Not Allowed")

          {"GET", "/page"} ->
            conn
            |> Plug.Conn.put_resp_header("location", "/final")
            |> Plug.Conn.send_resp(301, "")

          {"GET", "/final"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "text/html")
            |> Plug.Conn.send_resp(200, "<html></html>")
        end
      end)

      assert {:ok, meta, _events} = Preflight.HTTP.execute("https://example.com/page")
      assert meta.status == 200
      assert meta.method == "GET"
      assert meta.final_url =~ "/final"
    end

    test "GET fallback propagates transport errors" do
      call_count = :counters.new(1, [:atomics])

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        :counters.add(call_count, 1, 1)

        case :counters.get(call_count, 1) do
          1 -> Plug.Conn.send_resp(conn, 405, "Method Not Allowed")
          _ -> Req.Test.transport_error(conn, :nxdomain)
        end
      end)

      assert {:error, %Req.TransportError{reason: :nxdomain}} =
               Preflight.HTTP.execute("https://example.com")
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

      assert {:ok, meta, _events} = Preflight.HTTP.execute("https://example.com")
      assert meta.content_type == nil
    end
  end
end
