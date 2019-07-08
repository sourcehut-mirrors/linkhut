defmodule Linkhut.Web.SessionController do
  use Linkhut.Web, :controller

  alias Linkhut.Web.Auth.Guardian.Plug, as: GuardianPlug

  def new(conn, _) do
    cond do
      GuardianPlug.current_resource(conn) ->
        conn
        |> redirect(to: Routes.user_path(conn, :show))

      true ->
        conn
        |> render("new.html")
    end
  end

  def create(conn, %{"session" => %{"email" => user, "password" => pass}}) do
    case Linkhut.Web.Auth.login_by_email_and_pass(conn, user, pass) do
      {:ok, conn} ->
        conn
        |> put_flash(:info, "Welcome back")
        |> redirect(to: Routes.user_path(conn, :show))

      {:error, _reason, conn} ->
        conn
        |> put_flash(:error, "Wrong username/password")
        |> render("new.html")
    end
  end

  def delete(conn, _) do
    conn
    |> GuardianPlug.sign_out()
    |> redirect(to: "/")
  end

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {:invalid_token, _reason}, opts) do
    # The token is invalid, let's revoke it and sign out
    token = GuardianPlug.current_token(conn, opts)
    Linkhut.Web.Auth.Guardian.revoke(token, opts)

    conn
    |> GuardianPlug.sign_out()
    |> redirect(to: Routes.session_path(conn, :new))
  end

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, _reason}, _opts) do
    body = Jason.encode!(%{message: to_string(type)})
    send_resp(conn, 401, body)
  end
end
