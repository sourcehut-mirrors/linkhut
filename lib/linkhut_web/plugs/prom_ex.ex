defmodule LinkhutWeb.Plugs.PromEx do
  @moduledoc """
  Use this plug in your Endpoint file to expose your metrics. The following options are supported by this plug:

  * `:prom_ex_module` - The PromEx module whose metrics will be published through this particular plug
  * `:path` - The path through which your metrics can be accessed (default is "/metrics")
  """

  def init(opts) do
    PromEx.Plug.init(opts)
  end

  def call(%Plug.Conn{request_path: metrics_path} = conn, %{metrics_path: metrics_path} = opts) do
    username = Linkhut.Config.get!([Linkhut, :prometheus, :username])
    password = Linkhut.Config.get!([Linkhut, :prometheus, :password])

    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
    |> maybe_call_prom_ex(opts)
  end

  def call(conn, _), do: conn

  def maybe_call_prom_ex(%Plug.Conn{halted: true} = conn, _opts), do: conn

  def maybe_call_prom_ex(conn, opts) do
    conn
    |> PromEx.Plug.call(opts)
  end
end
