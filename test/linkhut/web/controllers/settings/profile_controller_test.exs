defmodule Linkhut.Web.Settings.ProfileControllerTest do
  use Linkhut.Web.ConnCase

  import Linkhut.Web.Auth.Guardian

  describe "show/2" do
    test "Responds with user info if the user is logged in", %{conn: conn} do
      user = insert(:user)
      {:ok, token, _} = encode_and_sign(user, %{}, token_type: :access)

      response =
        conn
        |> put_req_header("authorization", "bearer: " <> token)
        |> get(Routes.profile_path(conn, :show))
        |> html_response(200)

      assert response =~ user.username
      assert response =~ user.email
      assert response =~ user.bio
    end

    test "Responds with a redirect to login page if the user is logged out", %{conn: conn} do
      redirect_path =
        conn
        |> get(Routes.profile_path(conn, :show))
        |> redirected_to(302)

      assert redirect_path == "/login"
    end
  end
end
