defmodule LinkhutWeb.ResetPasswordControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Accounts
  alias Linkhut.Repo
  import Linkhut.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /_/reset-password" do
    test "renders the reset password page", %{conn: conn} do
      conn = get(conn, ~p"/_/reset-password")
      response = html_response(conn, 200)
      assert response =~ "Forgot your password?"
    end
  end

  describe "POST /_/reset-password" do
    @tag :capture_log
    test "sends a new reset password token", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/_/reset-password", %{
          "credential" => %{"email" => user.credential.email}
        })

      assert redirected_to(conn) == ~p"/_/login"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/_/reset-password", %{
          "credential" => %{"email" => "unknown@example.com"}
        })

      assert redirected_to(conn) == ~p"/_/login"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.all(Accounts.UserToken) == []
    end
  end

  describe "GET /_/reset-password/:token" do
    setup %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_reset_password_instructions(user, url)
        end)

      %{token: token}
    end

    test "renders reset password", %{conn: conn, token: token} do
      conn = get(conn, ~p"/_/reset-password/#{token}")
      assert html_response(conn, 200) =~ "Reset password"
    end

    test "does not render reset password with invalid token", %{conn: conn} do
      conn = get(conn, ~p"/_/reset-password/oops")
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Reset password link is invalid or it has expired"
    end
  end

  describe "PUT /_/reset-password/:token" do
    setup %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_reset_password_instructions(user, url)
        end)

      %{token: token}
    end

    test "resets password once", %{conn: conn, user: user, token: token} do
      conn =
        put(conn, ~p"/_/reset-password/#{token}", %{
          "credential" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == ~p"/_/login"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Password reset successfully"

      assert Accounts.authenticate_by_username_password(user.username, "new valid password")
    end

    test "does not reset password on invalid password", %{conn: conn, token: token} do
      conn =
        put(conn, ~p"/_/reset-password/#{token}", %{
          "credential" => %{
            "password" => "short",
            "password_confirmation" => "short"
          }
        })

      assert html_response(conn, 200) =~ "should be at least 6 character(s)"
    end

    test "does not reset password on non-matching password confirmation", %{
      conn: conn,
      token: token
    } do
      conn =
        put(conn, ~p"/_/reset-password/#{token}", %{
          "credential" => %{
            "password" => "foo bar baz",
            "password_confirmation" => "foo bar qux"
          }
        })

      assert html_response(conn, 200) =~ "does not match password"
    end

    test "does not reset password with invalid token", %{conn: conn} do
      conn = put(conn, ~p"/_/reset-password/oops")
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Reset password link is invalid or it has expired"
    end
  end
end
