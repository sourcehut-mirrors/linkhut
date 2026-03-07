defmodule LinkhutWeb.Api.IFTTT.TestControllerTest do
  # NOTE: Cannot be async: true — setup mutates global Application config
  use LinkhutWeb.ConnCase

  alias Linkhut.Oauth

  @service_key Linkhut.Config.ifttt(:service_key)

  setup %{conn: conn} do
    user = Linkhut.AccountsFixtures.user_fixture()

    {:ok, app} =
      Oauth.create_application(user, %{
        "name" => "IFTTT Test App",
        "redirect_uri" => "http://example.com/callback"
      })

    original_ifttt = Application.get_env(:linkhut, Linkhut.IFTTT, [])

    updated = Keyword.merge(original_ifttt, user_id: user.id, application: app.uid)

    Application.put_env(:linkhut, Linkhut.IFTTT, updated)
    on_exit(fn -> Application.put_env(:linkhut, Linkhut.IFTTT, original_ifttt) end)

    conn =
      conn
      |> put_req_header("ifttt-service-key", @service_key)
      |> put_req_header("accept", "application/json")

    %{conn: conn, user: user, app: app}
  end

  describe "POST /_/ifttt/v1/test/setup" do
    test "returns test setup data with valid service key", %{conn: conn} do
      body =
        conn
        |> post(~p"/_/ifttt/v1/test/setup")
        |> json_response(200)

      assert %{"data" => data} = body
      assert is_binary(data["accessToken"])
      assert %{"actions" => _, "actionRecordSkipping" => _, "triggers" => _} = data["samples"]
    end

    test "returned accessToken has ifttt scope", %{conn: conn} do
      body =
        conn
        |> post(~p"/_/ifttt/v1/test/setup")
        |> json_response(200)

      token_string = body["data"]["accessToken"]
      token = Linkhut.Repo.get_by!(Linkhut.Oauth.AccessToken, token: token_string)
      assert token.scopes == "ifttt"
    end

    test "samples contain expected structure", %{conn: conn} do
      body =
        conn
        |> post(~p"/_/ifttt/v1/test/setup")
        |> json_response(200)

      samples = body["data"]["samples"]

      assert %{"url" => _, "tags" => _, "notes" => _, "title" => _} =
               samples["actions"]["add_public_link"]

      assert %{"url" => _, "tags" => _, "notes" => _, "title" => _} =
               samples["actions"]["add_private_link"]

      assert %{"tag" => "linkhut"} = samples["triggers"]["new_public_link_tagged"]
    end

    test "returns 401 without service key", %{conn: conn} do
      conn
      |> delete_req_header("ifttt-service-key")
      |> post(~p"/_/ifttt/v1/test/setup")
      |> response(401)
    end
  end
end
