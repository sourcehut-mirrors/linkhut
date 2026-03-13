defmodule LinkhutWeb.Plugs.GlobalAssigns do
  @behaviour Plug

  @moduledoc """
  Plug to set some global assigns
  """

  import Plug.Conn
  alias Linkhut.{Accounts.Preferences, Archiving, Links}

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
      |> assign(:can_create_archives?, Archiving.can_create_archives?(user))
      |> assign(:can_view_archives?, Archiving.can_view_archives?(user))
      |> assign(:preferences, Preferences.get_or_default(user))
    else
      conn
      |> assign(:logged_in?, false)
      |> assign(:can_create_archives?, false)
      |> assign(:can_view_archives?, false)
      |> assign(:preferences, %Linkhut.Accounts.Preferences.UserPreference{})
    end
  end
end
