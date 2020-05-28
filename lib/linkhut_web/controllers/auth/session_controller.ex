defmodule LinkhutWeb.Auth.SessionController do
  use LinkhutWeb, :controller

  plug :put_view, LinkhutWeb.AuthView

  alias Linkhut.Accounts

  def new(conn, _) do
    if get_session(conn, :current_user) != nil do
      conn
      |> redirect(to: get_session(conn, :login_redirect_path) || "/")
    else
      conn
      |> render("login.html")
    end
  end

  def create(conn, %{"session" => %{"username" => username, "password" => pass}}) do
    case Accounts.authenticate_by_username_password(username, pass) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> redirect(to: get_session(conn, :login_redirect_path) || "/")

      {:error, :unauthorized} ->
        conn
        |> put_flash(:error, "Wrong username/password")
        |> render("login.html")
    end
  end

  def delete(conn, _) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end
end
