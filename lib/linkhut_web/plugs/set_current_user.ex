defmodule LinkhutWeb.Plugs.SetCurrentUser do
  @behaviour Plug

  import Plug.Conn
  alias Linkhut.Accounts

  @moduledoc false

  @impl true
  def init(opts \\ []), do: opts

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
      Accounts.get_user!(user_id)
    else
      nil
    end
  end
end
