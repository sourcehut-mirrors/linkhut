defmodule LinkhutWeb.Settings.EmailConfirmationController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts

  def create(conn, _) do
    if user = conn.assigns[:current_user] do
      if Accounts.current_email_unconfirmed?(user) do
        Accounts.deliver_email_confirmation_instructions(
          user,
          &url(~p"/_/confirm?#{%{token: Base.url_encode64(&1)}}")
        )
      end
    end

    conn
    |> put_flash(
      :info,
      "Check your mailbox for instructions on how to complete your e-mail verification."
    )
    |> redirect(to: Routes.link_path(conn, :show))
  end

  def confirm(conn, %{"token" => token}) do
    with {:ok, token} <- Base.url_decode64(token),
         {:ok, value} <- Accounts.confirm_email(token) do
      case value do
        # If the email was already confirmed, we redirect without
        # a warning message.
        :already_confirmed ->
          redirect(conn, to: "/")

        _ ->
          conn
          |> put_flash(:info, "Email confirmed successfully.")
          |> redirect(to: "/")
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Email confirmation link is invalid or it has expired.")
        |> redirect(to: "/")
    end
  end
end
