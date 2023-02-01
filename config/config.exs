# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :linkhut,
  ecto_repos: [Linkhut.Repo]

# Configures the endpoint
config :linkhut, LinkhutWeb.Endpoint,
  url: [host: "localhost"],
  static_url: [path: "/_"],
  secret_key_base: "mlPw70YW1sAUSrz5sF/LPkteFQ7Q75zutsNjXVNNDOpTag5Opi0WjVGIESGmddDd",
  render_errors: [view: LinkhutWeb.ErrorView, accepts: ~w(html json xml)],
  pubsub_server: Linkhut.PubSub,
  live_view: [signing_salt: "b58amlvXfHSJ+dhn5yTMgbiMwJubVUHf"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :mime, :types, %{
  "application/xml" => ["xml"]
}

config :phoenix_copy,
  default: [
    source: Path.expand("../assets/static/", __DIR__),
    destination: Path.expand("../priv/static/", __DIR__)
  ]

config :dart_sass,
  version: "1.49.11",
  default: [
    args: ~w(css/app.scss ../priv/static/css/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures OAuth
config :linkhut, ExOauth2Provider,
  repo: Linkhut.Repo,
  resource_owner: Linkhut.Accounts.User,
  access_grant: Linkhut.Oauth.AccessGrant,
  access_token: Linkhut.Oauth.AccessToken,
  application: Linkhut.Oauth.Application,
  force_ssl_in_redirect_uri: true,
  access_token_expires_in: 365 * 24 * 60 * 60,
  use_refresh_token: true,
  revoke_refresh_token_on_use: false,
  optional_scopes:
    ["ifttt"] ++ for(scope <- ~w(posts tags), access <- ~w(read write), do: "#{scope}:#{access}")

config :linkhut, PhoenixOauth2Provider,
  web_module: LinkhutWeb,
  current_resource_owner: :current_user

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
