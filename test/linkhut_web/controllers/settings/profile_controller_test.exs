defmodule LinkhutWeb.Settings.ProfileControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Accounts
  import Linkhut.AccountsFixtures

  setup {LinkhutWeb.ConnCase, :register_and_log_in_user}

  describe "GET /_/profile" do
    test "Responds with user info if the user is logged in", %{conn: conn, user: user} do
      response =
        conn
        |> get(Routes.profile_path(conn, :show))
        |> html_response(200)

      assert response =~ user.username
      assert response =~ user.credential.email
      assert response =~ user.bio
    end

    test "Responds with a redirect to login page if the user is logged out" do
      conn = build_conn()

      redirect_path =
        conn
        |> get(Routes.profile_path(conn, :show))
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end
  end

  describe "PUT /_/profile" do
    test "updates the user bio", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/_/profile", %{
          "user" => %{
            "bio" => "Super Awesome Bio"
          }
        })

      assert redirected_to(conn) == ~p"/_/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Profile updated"

      assert Accounts.get_user!(user.id).bio != user.bio
    end

    @tag :capture_log
    test "updates the user email", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/_/profile", %{
          "user" => %{
            "credential" => %{"email" => unique_user_email()}
          }
        })

      assert redirected_to(conn) == ~p"/_/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Profile updated"

      assert Accounts.get_user_by_email(user.credential.email)
    end

    test "does not update email on invalid data", %{conn: conn} do
      conn =
        put(conn, ~p"/_/profile", %{
          "user" => %{
            "credential" => %{"email" => "with spaces"}
          }
        })

      response = html_response(conn, 200)
      assert response =~ "has invalid format"
    end
  end

  describe "GET /_/profile/delete" do
    @tag token_inserted_at: DateTime.add(DateTime.utc_now(), -11, :minute)
    test "redirects if user is not in sudo mode", %{conn: conn} do
      conn =
        conn
        |> get(~p"/_/profile/delete")

      assert redirected_to(conn) == ~p"/_/login"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must re-authenticate to access this page."
    end

    test "shows form if user is in sudo mode", %{conn: conn} do
      conn =
        conn
        |> get(~p"/_/profile/delete")

      response = html_response(conn, 200)
      assert response =~ "Permanently delete account"
    end
  end

  describe "PUT /_/profile/delete" do
    test "does not delete user when confirmation checkbox is not checked", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/_/profile/delete", %{
        "delete_form" => %{

        }
        })

      assert html_response(conn, 200) =~ "Please confirm you want to delete your account"

      assert Accounts.get_user(user.username)
    end

    test "deletes user when confirmation checkbox is checked", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/_/profile/delete", %{
          "delete_form" => %{ "confirmed" => "true" }
        })

      assert redirected_to(conn) == ~p"/"

      refute Accounts.get_user(user.username)
    end
  end
end
