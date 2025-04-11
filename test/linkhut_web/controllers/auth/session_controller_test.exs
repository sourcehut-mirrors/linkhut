defmodule LinkhutWeb.UserSessionControllerTest do
  use LinkhutWeb.ConnCase

  import Linkhut.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /_/login" do
    test "renders log in page", %{conn: conn} do
      conn = get(conn, ~p"/_/login")
      response = html_response(conn, 200)
      assert response =~ "Log in"
      assert response =~ ~p"/_/register"
      assert response =~ "Forgot your password?"
    end

    test "doesn't show 'forgot your password?' if already logged in", %{conn: conn, user: user} do
      conn = conn |> LinkhutWeb.ConnCase.log_in_user(user) |> get(~p"/_/login")
      response = html_response(conn, 200)
      refute response =~ "Forgot your password?"
    end
  end

  describe "POST /_/login" do
    test "logs the user in", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/_/login", %{
          "session" => %{"username" => user.username, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.username
      assert response =~ ~p"/_/profile"
      assert response =~ ~p"/_/logout"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/_/login", %{
          "session" => %{
            "username" => user.username,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
    end

    test "emits error message with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/_/login", %{
          "session" => %{"username" => user.username, "password" => "invalid_password"}
        })

      response = html_response(conn, 200)
      assert response =~ "Log in"
      assert response =~ "Wrong username/password"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Wrong username/password"
    end
  end

  describe "DELETE /_/logout" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> LinkhutWeb.ConnCase.log_in_user(user) |> delete(~p"/_/logout")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/_/logout")
      assert redirected_to(conn) == ~p"/_/login"
      refute get_session(conn, :user_token)
    end
  end
end
