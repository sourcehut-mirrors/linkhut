defmodule LinkhutWeb.Plugs.GlobalAssigns do
  @behaviour Plug

  @moduledoc """
  Plug to set some global assigns
  """

  import Plug.Conn
  alias LinkhutWeb.Viewer

  @doc false
  @impl true
  def init([]), do: false

  @doc false
  @impl true
  def call(conn, _) do
    if user = conn.assigns[:current_user] do
      conn
      |> assign(:viewer, Viewer.for_user(user))
    else
      conn
      |> assign(:viewer, Viewer.anonymous())
    end
  end
end
