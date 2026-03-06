defmodule LinkhutWeb.Api.IFTTT.UserControllerTest do
  use LinkhutWeb.ConnCase

  @moduletag scopes: "ifttt"

  setup {LinkhutWeb.ConnCase, :register_and_set_up_api_token}

  describe "GET /_/ifttt/v1/user/info" do
    test "returns user info with valid token", %{conn: conn, user: user} do
      body =
        conn
        |> get(~p"/_/ifttt/v1/user/info")
        |> json_response(200)

      assert body["data"]["name"] == user.username
      assert body["data"]["id"] == "#{user.id}"
      assert body["data"]["url"] =~ "/~#{user.username}"
    end

    test "returns 401 without auth" do
      unauthenticated_api_conn()
      |> get(~p"/_/ifttt/v1/user/info")
      |> json_response(401)
    end

    @tag scopes: "posts:read"
    test "returns 401 with wrong scope", %{conn: conn} do
      conn
      |> get(~p"/_/ifttt/v1/user/info")
      |> json_response(401)
    end
  end
end
