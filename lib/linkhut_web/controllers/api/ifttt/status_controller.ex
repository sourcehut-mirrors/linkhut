defmodule LinkhutWeb.Api.IFTTT.StatusController do
  use LinkhutWeb, :controller

  alias Plug.Conn

  def ok(conn, _params) do
    conn
    |> Conn.send_resp(200, "")
  end
end
