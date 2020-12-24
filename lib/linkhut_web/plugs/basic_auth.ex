defmodule LinkhutWeb.Plugs.BasicAuth do
  @moduledoc false
  @behaviour Plug

  import Plug.BasicAuth
  import Plug.Conn
  alias Linkhut.Accounts

  @doc false
  @impl true
  def init([]), do: false

  @doc false
  @impl true
  def call(conn, _) do
    with {user, pass} <- parse_basic_auth(conn),
         {:ok, %Accounts.User{} = user} <- Accounts.authenticate_by_username_password(user, pass) do
      assign(conn, :current_user, user)
    else
      _ -> conn |> request_basic_auth(realm: "API") |> halt()
    end
  end
end
