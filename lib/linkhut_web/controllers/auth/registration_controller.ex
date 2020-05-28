defmodule LinkhutWeb.Auth.RegistrationController do
  use LinkhutWeb, :controller

  plug :put_view, LinkhutWeb.AuthView

  alias Linkhut.Accounts
  alias Linkhut.Accounts.User

  def new(conn, _params) do
    if get_session(conn, :current_user) != nil do
      conn
      |> redirect(to: Routes.profile_path(conn, :show))
    else
      conn
      |> render("register.html", changeset: Accounts.change_user(%User{}))
    end
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> put_flash(:info, "Welcome to linkhut!")
        |> redirect(to: Routes.link_path(conn, :index))

      {:error, changeset} ->
        conn
        |> render("register.html", changeset: changeset)
    end
  end
end
