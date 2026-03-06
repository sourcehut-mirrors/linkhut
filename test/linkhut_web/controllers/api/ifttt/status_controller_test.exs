defmodule LinkhutWeb.Api.IFTTT.StatusControllerTest do
  use LinkhutWeb.ConnCase

  @service_key Linkhut.Config.ifttt(:service_key)

  defp ifttt_conn(conn) do
    conn
    |> put_req_header("ifttt-service-key", @service_key)
  end

  describe "GET /_/ifttt/v1/status" do
    test "returns 200 with valid service key", %{conn: conn} do
      conn
      |> ifttt_conn()
      |> get(~p"/_/ifttt/v1/status")
      |> response(200)
    end

    test "returns 401 without service key", %{conn: conn} do
      conn
      |> get(~p"/_/ifttt/v1/status")
      |> response(401)
    end

    test "returns 401 with wrong service key", %{conn: conn} do
      conn
      |> put_req_header("ifttt-service-key", "wrongkey")
      |> get(~p"/_/ifttt/v1/status")
      |> response(401)
    end
  end
end
