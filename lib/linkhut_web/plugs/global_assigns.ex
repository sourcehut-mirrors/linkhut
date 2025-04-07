defmodule LinkhutWeb.Plugs.GlobalAssigns do
  @behaviour Plug

  @moduledoc """
  Plug to set some global assigns
  """

  import Plug.Conn
  alias Linkhut.Links

  @doc false
  @impl true
  def init([]), do: false

  @doc false
  @impl true
  def call(conn, _) do
    if user = conn.assigns[:current_user] do
      conn
      |> assign(:logged_in?, true)
      |> assign(:unread_count, Links.unread_count(user.id))
    else
      conn
      |> assign(:logged_in?, false)
    end
  end
end
