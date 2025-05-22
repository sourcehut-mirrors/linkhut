defmodule LinkhutWeb.Auth.RegistrationController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts
  alias Linkhut.Accounts.User
  alias LinkhutWeb.UserAuth

  def new(conn, _params) do
    if conn.assigns[:current_user] != nil do
      conn
      |> redirect(to: Routes.profile_path(conn, :show))
    else
      conn
      |> render(:register, changeset: Accounts.change_user(%User{}))
    end
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        Accounts.deliver_email_confirmation_instructions(
          user,
          &url(~p"/_/confirm/#{&1}")
        )

        conn
        |> put_flash(:info, "Welcome to linkhut!")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        conn
        |> render(:register, changeset: changeset)
    end
  end
end
