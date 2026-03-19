defmodule Linkhut.Archiving.Crawler.WaybackMachineTest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.Crawler.WaybackMachine
  alias Linkhut.Archiving.Crawler.Context

  describe "source_type/0" do
    test "returns wayback" do
      assert WaybackMachine.source_type() == "wayback"
    end
  end

  describe "network_access/0" do
    test "returns :third_party" do
      assert WaybackMachine.network_access() == :third_party
    end
  end

  describe "meta/0" do
    test "returns Wayback Machine metadata" do
      assert %{tool_name: "Wayback CDX API", tool_version: nil, version: "1"} =
               WaybackMachine.meta()
    end
  end

  describe "queue/0" do
    test "returns :crawler" do
      assert WaybackMachine.queue() == :crawler
    end
  end

  describe "rate_limit/0" do
    test "returns 40 requests per minute" do
      assert WaybackMachine.rate_limit() == {60_000, 40}
    end
  end

  describe "can_handle?/2" do
    test "returns true for HTTP URLs" do
      assert WaybackMachine.can_handle?("http://example.com/page", nil)
    end

    test "returns true for HTTPS URLs" do
      assert WaybackMachine.can_handle?("https://example.com/page", nil)
    end

    test "returns true even with nil preflight_meta" do
      assert WaybackMachine.can_handle?("https://example.com", nil)
    end

    test "returns false for FTP URLs" do
      refute WaybackMachine.can_handle?("ftp://example.com/file", nil)
    end

    test "returns false for localhost" do
      refute WaybackMachine.can_handle?("http://localhost/page", nil)
    end

    test "returns false for 127.0.0.1" do
      refute WaybackMachine.can_handle?("http://127.0.0.1/page", nil)
    end

    test "returns false for URLs without host" do
      refute WaybackMachine.can_handle?("not-a-url", nil)
    end
  end

  describe "fetch/1" do
    setup do
      context = %Context{
        user_id: 1,
        link_id: 1,
        url: "https://example.com/page",
        snapshot_id: 1,
        link_inserted_at: ~U[2025-03-01 10:00:00Z]
      }

      %{context: context}
    end

    test "returns closest capture", %{context: context} do
      stub_cdx_response([
        ["20250301120000", "https://example.com/page", "200", "text/html", "ABC123", "4567"]
      ])

      assert {:ok, {:external, result}} = WaybackMachine.fetch(context)
      assert result.url == "https://web.archive.org/web/20250301120000/https://example.com/page"
      assert result.timestamp == "20250301120000"
      assert result.response_code == 200
      assert result.content_type == "text/html"
      assert result.digest == "ABC123"
      assert result.content_length == 4567
    end

    test "handles nil link_inserted_at by using current time", %{context: context} do
      context = %{context | link_inserted_at: nil}

      stub_cdx_response([
        ["20250301120000", "https://example.com/page", "200", "text/html", "ABC123", "4567"]
      ])

      assert {:ok, {:external, _result}} = WaybackMachine.fetch(context)
    end

    test "returns :not_available when no snapshot exists", %{context: context} do
      stub_cdx_response([])

      assert {:ok, :not_available} = WaybackMachine.fetch(context)
    end

    test "returns retryable error when API returns 5xx status", %{context: context} do
      Req.Test.stub(WaybackMachine, fn conn ->
        Plug.Conn.send_resp(conn, 503, "Service Unavailable")
      end)

      assert {:error, %{msg: "Wayback API error: HTTP 503"}} = WaybackMachine.fetch(context)
    end

    test "returns retryable error when API returns 429 status", %{context: context} do
      Req.Test.stub(WaybackMachine, fn conn ->
        Plug.Conn.send_resp(conn, 429, "Too Many Requests")
      end)

      assert {:error, %{msg: "Wayback API rate limited"}} = WaybackMachine.fetch(context)
    end

    test "returns non-retryable error when API returns 4xx status", %{context: context} do
      Req.Test.stub(WaybackMachine, fn conn ->
        Plug.Conn.send_resp(conn, 400, "Bad Request")
      end)

      assert {:error, %{msg: "Wayback API error: HTTP 400"}, :noretry} =
               WaybackMachine.fetch(context)
    end

    test "returns :not_available for empty body", %{context: context} do
      Req.Test.stub(WaybackMachine, fn conn ->
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, :not_available} = WaybackMachine.fetch(context)
    end

    test "returns retryable error for unexpected JSON structure", %{context: context} do
      Req.Test.stub(WaybackMachine, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"error" => "blocked"}))
      end)

      assert {:error, %{msg: msg}} = WaybackMachine.fetch(context)
      assert msg =~ "Wayback API returned invalid response"
    end
  end

  defp stub_cdx_response(rows) do
    Req.Test.stub(WaybackMachine, fn conn ->
      header = ["timestamp", "original", "statuscode", "mimetype", "digest", "length"]
      body = Jason.encode!([header | rows])

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, body)
    end)
  end
end
