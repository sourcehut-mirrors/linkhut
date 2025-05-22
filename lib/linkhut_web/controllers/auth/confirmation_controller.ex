defmodule LinkhutWeb.Auth.ConfirmationController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts

  def create(conn, _) do
    if user = conn.assigns[:current_user] do
      Accounts.deliver_email_confirmation_instructions(
        user,
        &url(~p"/_/confirm/#{&1}")
      )
    end

    conn
    |> put_flash(
      :info,
      "Check your mailbox for instructions on how to complete your e-mail verification."
    )
    |> redirect(to: ~p"/")
  end

  def update(conn, %{"token" => token}) do
    case Accounts.confirm_user(conn.assigns[:current_user], token) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Email confirmed successfully.")
        |> redirect(to: ~p"/")

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case conn.assigns do
          %{current_user: %{type: type}}
          when type != :unconfirmed ->
            redirect(conn, to: ~p"/")

          %{} ->
            conn
            |> put_flash(:error, "Email confirmation link is invalid or it has expired.")
            |> redirect(to: ~p"/")
        end
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_email(conn.assigns.current_user, token) do
      :ok ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/_/profile")

      :error ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/_/profile")
    end
  end
end
