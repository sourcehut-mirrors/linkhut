defmodule Linkhut.Archiving.Preflight.HTTPTest do
  use ExUnit.Case, async: false

  alias Linkhut.Archiving.Preflight
  alias Linkhut.Archiving.PreflightMeta

  describe "check_url/1" do
    test "classifies a URL" do
      for {url, expected} <- [
            {"not-a-url", {:unusable, %{reason: :invalid_url}}},
            {"http:///page", {:unusable, %{reason: :invalid_url}}},
            {"ftp://example.com/file",
             {:unusable, %{reason: :unsupported_scheme, scheme: "ftp"}}},
            {"http://127.0.0.1/",
             {:unusable, %{reason: :reserved_address, host: "127.0.0.1", range: :loopback}}},
            {"http://nonexistent.invalid/", {:unreachable, {:dns_failed, "nonexistent.invalid"}}}
          ] do
        assert Preflight.HTTP.check_url(url) == expected, "for #{url}"
      end
    end
  end

  describe "execute/2" do
    test "returns PreflightMeta with correct fields on success" do
      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "Text/HTML; charset=UTF-8")
        |> Plug.Conn.put_resp_header("content-length", "1234")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, %PreflightMeta{} = meta} = Preflight.HTTP.execute("https://example.com/page")

      assert meta.scheme == "https"
      assert meta.content_type == "text/html"
      assert meta.content_length == 1234
      assert meta.status == 200
      assert meta.method == "HEAD"
      assert meta.final_url =~ "example.com"
    end

    test "gives up after five redirects" do
      test_pid = self()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        send(test_pid, :requested)
        hop = conn.request_path |> String.trim_leading("/") |> String.to_integer()

        conn
        |> Plug.Conn.put_resp_header("location", "/#{hop + 1}")
        |> Plug.Conn.send_resp(302, "")
      end)

      assert {:unreachable, %Req.TooManyRedirectsError{max_redirects: 5}} =
               Preflight.HTTP.execute("https://example.com/0")

      for _ <- 0..5, do: assert_received(:requested)
      refute_received :requested
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

      assert {:ok, meta} = Preflight.HTTP.execute("https://example.com/page")
      assert meta.status == 200
      assert meta.method == "GET"
      assert meta.final_url =~ "/final"
    end
  end
end
