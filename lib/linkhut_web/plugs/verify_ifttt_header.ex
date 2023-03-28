defmodule LinkhutWeb.Plugs.VerifyIFTTTHeader do
  @behaviour Plug
  @moduledoc """
  Use this plug to verify the value of the IFTTT service key header: `IFTTT-Service-Key`
  """

  import Plug.Conn, only: [halt: 1]

  @header "IFTTT-Service-Key" |> String.downcase()

  @doc false
  @impl true
  def init(opts), do: opts

  @doc false
  @impl true
  def call(conn, _) do
    service_key = Keyword.get(Application.get_env(:linkhut, :ifttt), :service_key, "")
    case Plug.Conn.get_req_header(conn, @header) do
      [value | _] -> if String.trim(value) == service_key, do: conn, else: unauthorized(conn)
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
