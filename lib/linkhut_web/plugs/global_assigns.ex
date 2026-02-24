defmodule LinkhutWeb.Plugs.GlobalAssigns do
  @behaviour Plug

  @moduledoc """
  Plug to set some global assigns
  """

  import Plug.Conn
  alias Linkhut.{Archiving, Links}

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
      |> assign(:archiving_enabled?, Archiving.enabled_for_user?(user))
    else
      conn
      |> assign(:logged_in?, false)
      |> assign(:archiving_enabled?, false)
    end
  end
end
