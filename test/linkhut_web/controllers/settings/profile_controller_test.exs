defmodule LinkhutWeb.Settings.ProfileControllerTest do
  use LinkhutWeb.ConnCase

  describe "show/2" do
    test "Responds with user info if the user is logged in", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> assign(:current_user, user)
        |> get(Routes.profile_path(conn, :show))
        |> html_response(200)

      assert response =~ user.username
      assert response =~ user.credential.email
      assert response =~ user.bio
    end

    test "Responds with a redirect to login page if the user is logged out", %{conn: conn} do
      redirect_path =
        conn
        |> get(Routes.profile_path(conn, :show))
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end
  end
end
