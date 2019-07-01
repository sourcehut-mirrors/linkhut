defmodule Linkhut.Web.SessionController do
  use Linkhut.Web, :controller

  alias Linkhut.Web.Auth.Guardian.Plug, as: GuardianPlug

  def new(conn, _) do
    render conn, "new.html"
  end

  def create(conn, %{"session" => %{"email" => user, "password" => pass}}) do
    case Linkhut.Web.Auth.login_by_email_and_pass(conn, user, pass) do
      {:ok, conn} ->
        logged_in_user = GuardianPlug.current_resource(conn)
        conn
        |> put_flash(:info, "Welcome back")
        |> redirect(to: Routes.user_path(conn, :show, logged_in_user))
      {:error, _reason, conn} ->
        conn
        |> put_flash(:error, "Wrong username/password")
        |> render("new.html")
    end
  end

  def delete(conn, _) do
    conn
    |> GuardianPlug.sign_out
    |> redirect(to: "/")
  end
end
