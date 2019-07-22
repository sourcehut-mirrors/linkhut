defmodule Linkhut.Web.Auth.SessionController do
  use Linkhut.Web, :controller

  plug :put_view, Linkhut.Web.AuthView

  alias Linkhut.Web.Auth.Guardian.Plug, as: GuardianPlug

  def new(conn, _) do
    cond do
      GuardianPlug.current_resource(conn) ->
        conn
        |> login(to: target_path(conn))

      true ->
        conn
        |> render("login.html")
    end
  end

  defp login(conn, to: path) do
    redirect(conn, to: path)
  end

  def create(conn, %{"session" => %{"username" => username, "password" => pass}}) do
    case Linkhut.Web.Auth.login_by_username_and_pass(conn, username, pass) do
      {:ok, conn} ->
        conn
        |> login(to: target_path(conn))

      {:error, _reason, conn} ->
        conn
        |> put_flash(:error, "Wrong username/password")
        |> render("login.html")
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
  def auth_error(conn, {_type, _reason}, _opts) do
    conn
    |> store_path_in_session()
    |> put_flash(:error, "Authentication required")
    |> redirect(to: Routes.session_path(conn, :new))
  end

  defp store_path_in_session(conn) do
    # Get HTTP method and url from conn
    method = conn.method
    path = conn.request_path

    # If conditions apply store path in session, else return conn unmodified
    case {method, !String.match?(path, ~r/session/)} do
      {"GET", true} ->
        put_session(conn, :login_redirect_path, path)

      {_, _} ->
        conn
    end
  end

  defp target_path(conn) do
    target_path = get_session(conn, :login_redirect_path) || "/"
    delete_session(conn, :login_redirect_path)
    target_path
  end
end
