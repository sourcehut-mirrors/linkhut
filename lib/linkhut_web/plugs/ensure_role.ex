defmodule LinkhutWeb.Plugs.EnsureRole do
  @moduledoc """
  This plug ensures that a user has a particular role.

  ## Example

      plug EnsureRole, [:user, :admin]

      plug EnsureRole, :admin
  """
  import Plug.Conn, only: [halt: 1]
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias LinkhutWeb.Router.Helpers, as: RouteHelpers
  alias Plug.Conn
  alias LinkhutWeb.Plugs.EnsureAuth

  @doc false
  @spec init(any()) :: any()
  def init(config), do: config

  @doc false
  @spec call(Conn.t(), atom() | binary() | [atom()] | [binary()]) :: Conn.t()
  def call(conn, roles) do
    conn
    |> EnsureAuth.get_user()
    |> has_role?(roles)
    |> maybe_halt(conn)
  end

  defp has_role?(nil, _roles), do: false
  defp has_role?(user, roles) when is_list(roles), do: Enum.any?(roles, &has_role?(user, &1))

  defp has_role?(%{roles: roles}, role) when is_atom(role) do
    Enum.any?(roles, fn r -> r == role end)
  end

  defp maybe_halt(true, conn), do: conn

  defp maybe_halt(_any, conn) do
    conn
    |> put_flash(:error, "Unauthorized access")
    |> redirect(to: RouteHelpers.session_path(conn, :new))
    |> halt()
  end
end
