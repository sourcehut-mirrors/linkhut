defmodule LinkhutWeb.Plugs.VerifyIFTTTHeader do
  @behaviour Plug
  @moduledoc """
  Use this plug to verify the value of the IFTTT service key header: `IFTTT-Service-Key`
  """

  import Plug.Conn, only: [halt: 1]

  @header "IFTTT-Service-Key" |> String.downcase()

  @doc false
  @impl true
  def init(_) do
    Keyword.get(Application.get_env(:linkhut, :ifttt), :service_key, "")
  end

  @doc false
  @impl true
  def call(conn, service_key) do
    case Plug.Conn.get_req_header(conn, @header) do
      [value] -> if value == service_key, do: conn, else: unauthorized(conn)
      _ -> unauthorized(conn)
    end
  end

  @doc false
  def unauthorized(conn) do
    conn
    |> Plug.Conn.send_resp(403, "Unauthorized")
    |> halt()
  end
end
