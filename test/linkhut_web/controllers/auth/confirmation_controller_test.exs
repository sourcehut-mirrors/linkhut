defmodule LinkhutWeb.ConfirmationControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Accounts
  alias Linkhut.Repo
  import Linkhut.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "POST /_/confirm" do
    @tag :capture_log
    test "sends a new confirmation token", %{conn: conn, user: user} do
      conn =
        conn
        |> LinkhutWeb.ConnCase.log_in_user(user)
        |> post(~p"/_/confirm")

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Check your mailbox for instructions on how to complete your e-mail verification."

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "does not send confirmation token if email is confirmed", %{conn: conn, user: user} do
      Repo.update!(Accounts.Credential.confirm_email_changeset(user.credential, %{}))

      conn =
        conn
        |> LinkhutWeb.ConnCase.log_in_user(user)
        |> post(~p"/_/confirm")

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Check your mailbox for instructions on how to complete your e-mail verification."

      refute Repo.get_by(Accounts.UserToken, user_id: user.id, context: "confirm")
    end
  end

  describe "GET /_/confirm/:token" do
    test "confirms the given token once", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_email_confirmation_instructions(user, url)
        end)

      conn =
        conn
        |> LinkhutWeb.ConnCase.log_in_user(user)
        |> get(~p"/_/confirm/#{token}")

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Email confirmed successfully"

      refute Accounts.get_user!(user.id) |> Accounts.current_email_unconfirmed?()
      refute Repo.get_by(Accounts.UserToken, user_id: user.id, context: "confirm")

      # When attempted again
      conn =
        build_conn()
        |> LinkhutWeb.ConnCase.log_in_user(user)
        |> get(~p"/_/confirm/#{token}")

      assert redirected_to(conn) == ~p"/"
      refute Phoenix.Flash.get(conn.assigns.flash, :error)

      # When logged in with another account

      conn =
        build_conn()
        |> LinkhutWeb.ConnCase.log_in_user(user_fixture())
        |> get(~p"/_/confirm/#{token}")

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email confirmation link is invalid or it has expired."
    end

    test "does not confirm email with invalid token", %{conn: conn, user: user} do
      conn =
        conn
        |> LinkhutWeb.ConnCase.log_in_user(user)
        |> get(~p"/_/confirm/%%%")

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email confirmation link is invalid or it has expired"

      assert Accounts.get_user!(user.id) |> Accounts.current_email_unconfirmed?()
    end
  end

  describe "GET /_/confirm-email/:token" do
    setup %{user: user} do
      email = "boob@example.com"

      token =
        extract_user_token(fn url ->
          {:ok, updated_user, current_email} =
            Accounts.apply_email_change(user, %{"credential" => %{"email" => email}})

          Accounts.deliver_update_email_instructions(updated_user, current_email, url)
        end)

      %{token: token, email: email}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      conn = get(conn |> LinkhutWeb.ConnCase.log_in_user(user), ~p"/_/confirm-email/#{token}")
      assert redirected_to(conn) == ~p"/_/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Email changed successfully"

      refute Accounts.get_user_by_email(user.credential.email)
      assert Accounts.get_user_by_email(email)

      conn = get(conn, ~p"/_/confirm-email/#{token}")

      assert redirected_to(conn) == ~p"/_/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      conn = get(conn |> LinkhutWeb.ConnCase.log_in_user(user), ~p"/_/confirm-email/oops")
      assert redirected_to(conn) == ~p"/_/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"

      assert Accounts.get_user_by_email(user.credential.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, ~p"/_/confirm-email/#{token}")
      assert redirected_to(conn) == ~p"/_/login"
    end
  end
end
