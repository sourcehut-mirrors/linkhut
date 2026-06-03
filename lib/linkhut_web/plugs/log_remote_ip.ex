defmodule LinkhutWeb.Plugs.LogRemoteIp do
  @behaviour Plug

  @moduledoc """
  The remote ip is added to the `Logger` metadata as `:remote_ip`. To see the
  remote ip in your log output, configure your logger formatter to include the `:remote_ip`
  metadata. For example:

      config :logger, :default_formatter, metadata: [:remote_ip]
  """

  @doc false
  @impl true
  def init([]), do: false

  @doc false
  @impl true
  def call(conn, _) do
    Logger.metadata(remote_ip: conn.remote_ip |> :inet.ntoa() |> to_string())
    conn
  end
end
