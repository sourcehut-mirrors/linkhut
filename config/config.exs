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
config :linkhut, Linkhut.Web.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "mlPw70YW1sAUSrz5sF/LPkteFQ7Q75zutsNjXVNNDOpTag5Opi0WjVGIESGmddDd",
  render_errors: [view: Linkhut.Web.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Linkhut.PubSub, adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configures Guardian
config :linkhut, Linkhut.Web.Auth.Guardian,
  issuer: "linkhut",
  secret_key: "secret"

# Configures TidyEx
# Note: there seems to be a typo in the application name (extra `t`: https://github.com/f34nk/tidy_ex/issues/5), this generates a warning at startup that is safe to ignore
# Note: for a full list of settings: https://api.html-tidy.org/tidy/tidylib_api_5.6.0/group__public__enumerations.html#ga3a1401652599150188a168dade7dc150
config :tidyt_ex,
  options: [
    {"TidyBodyOnly", "no"},
    {"TidyIndentContent", "yes"},
    {"TidyWrapLen", "0"}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
