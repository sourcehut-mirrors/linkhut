defmodule LinkhutWeb.Plugs.EnsureAuth do
  @behaviour Plug

  @moduledoc """
  Plug ensuring the requester is logged in.
  """

  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]
  import Plug.Conn
  alias Linkhut.Accounts
  alias LinkhutWeb.Router.Helpers, as: RouteHelpers

  @doc false
  @impl true
  def init([]), do: false

  @doc false
  @impl true
  def call(conn, _) do
    if user = get_user(conn) do
      assign(conn, :current_user, user)
    else
      auth_error!(conn)
    end
  end

  def get_user(conn) do
    case conn.assigns[:current_user] do
      nil ->
        fetch_user(conn)

      user ->
        user
    end
  end

  defp fetch_user(conn) do
    if user_id = get_session(conn, :user_id) do
      Accounts.get_user(user_id)
    else
      nil
    end
  end

  defp auth_error!(conn) do
    conn
    |> store_path_and_querystring_in_session()
    |> put_flash(:error, "Login required")
    |> redirect(to: RouteHelpers.session_path(conn, :new))
    |> halt()
  end

  defp store_path_and_querystring_in_session(conn) do
    # Get HTTP method and url from conn
    method = conn.method

    path =
      if conn.query_string != "" do
        conn.request_path <> "?" <> conn.query_string
      else
        conn.request_path
      end

    # If conditions apply store path in session, else return conn unmodified
    case method do
      "GET" ->
        put_session(conn, :login_redirect_path, path)

      _ ->
        conn
    end
  end
end
