defmodule LinkhutWeb.Plugs.AuthErrorHandler do
  @moduledoc """
  A default error handler that can be used for failed authentication
  """

  alias Plug.Conn

  @callback unauthorized(Conn.t(), map()) :: Conn.t()

  @doc false
  @spec unauthorized(Conn.t(), map()) :: Conn.t()
  def unauthorized(conn, _params) do
    conn
    |> Conn.put_resp_content_type("application/json")
    |> Conn.send_resp(401, Jason.encode!(%{errors: "Unauthorized"}))
  end
end
