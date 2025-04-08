defmodule LinkhutWeb.Auth.RegistrationController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts
  alias Linkhut.Accounts.User

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
        if Accounts.current_email_unconfirmed?(user) != nil do
          Accounts.deliver_email_confirmation_instructions(
            user,
            &url(~p"/_/confirm?#{%{token: Base.url_encode64(&1)}}")
          )
        end

        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> put_flash(:info, "Welcome to linkhut!")
        |> redirect(to: ~p"/")

      {:error, changeset} ->
        conn
        |> render(:register, changeset: changeset)
    end
  end
end
