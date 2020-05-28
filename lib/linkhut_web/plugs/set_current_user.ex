defmodule LinkhutWeb.Plugs.SetCurrentUser do
  @behaviour Plug

  @moduledoc """
  Plug responsible for setting the currently logged in `User` to the "assigns" storage under the key `:current_user`.
  """

  import Plug.Conn
  alias Linkhut.Accounts

  @doc false
  @impl true
  def init([]), do: false

  @doc false
  @impl true
  def call(conn, _) do
    if user = get_user(conn) do
      conn
      |> assign(:current_user, user)
      |> assign(:logged_in?, true)
    else
      conn
      |> assign(:current_user, nil)
      |> assign(:logged_in?, false)
      |> delete_session(:user_id)
    end
  end

  defp get_user(conn) do
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
end
