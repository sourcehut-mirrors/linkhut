defmodule LinkhutWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :linkhut

  # Serve at "/_/" the static files from "priv/static" directory.
  plug Plug.Static,
    at: "/_/",
    from: :linkhut,
    gzip: true,
    only: ~w(css fonts images js)

  # Serve robots.txt at "/" from "priv/static" directory
  plug Plug.Static,
    at: "/",
    from: :linkhut,
    gzip: true,
    only: LinkhutWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug Plug.Session,
    store: :cookie,
    key: "_linkhut_key",
    signing_salt: "i2qrSlZN",
    max_age: 6 * 30 * 24 * 60 * 60 # ~6 months

  plug LinkhutWeb.Plugs.FeedRedirect
  plug LinkhutWeb.Router

  socket "/live", Phoenix.LiveView.Socket
end
