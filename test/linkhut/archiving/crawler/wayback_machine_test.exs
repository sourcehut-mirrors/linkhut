defmodule Linkhut.Archiving.Crawler.WaybackMachineTest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.Crawler.WaybackMachine

  describe "accepts/1" do
    test "skips other schemes" do
      assert WaybackMachine.accepts("ftp://example.com/file") ==
               {:reject, %{reason: :unsupported_scheme, scheme: "ftp"}}
    end
  end

  describe "fetch/1" do
    @url "https://example.com/page"
    @opts [bookmarked_at: ~U[2025-03-01 10:00:00Z]]

    test "returns closest capture" do
      stub_cdx_response([
        ["20250301120000", "https://example.com/page", "200", "text/html", "ABC123", "4567"]
      ])

      assert {:ok, {:external, result}} = WaybackMachine.fetch(@url, @opts)
      assert result.url == "https://web.archive.org/web/20250301120000/https://example.com/page"
      assert result.timestamp == "20250301120000"
      assert result.response_code == 200
      assert result.content_type == "text/html"
      assert result.digest == "ABC123"
      assert result.content_length == 4567
    end

    test "maps CDX responses to a result" do
      for {label, stub, expected} <- [
            {"no captures", cdx_stub([]), {:ok, :not_available}},
            {"empty body", raw_stub(200, ""), {:ok, :not_available}},
            {"server error", raw_stub(503, "Service Unavailable"),
             {:error, %{msg: "Wayback API error: HTTP 503"}}},
            {"rate limited", raw_stub(429, "Too Many Requests"),
             {:error, %{msg: "Wayback API rate limited"}}},
            {"client error", raw_stub(400, "Bad Request"),
             {:error, %{msg: "Wayback API error: HTTP 400"}, :noretry}}
          ] do
        Req.Test.stub(WaybackMachine, stub)

        assert WaybackMachine.fetch(@url, @opts) == expected, "for #{label}"
      end
    end
  end

  defp cdx_stub(rows) do
    fn conn ->
      header = ["timestamp", "original", "statuscode", "mimetype", "digest", "length"]
      body = Jason.encode!([header | rows])

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, body)
    end
  end

  defp raw_stub(status, body), do: fn conn -> Plug.Conn.send_resp(conn, status, body) end

  defp stub_cdx_response(rows), do: Req.Test.stub(WaybackMachine, cdx_stub(rows))
end
