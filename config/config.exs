# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
