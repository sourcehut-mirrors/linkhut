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
  render_errors: [
    formats: [html: LinkhutWeb.ErrorHTML, json: LinkhutWeb.ErrorJSON, xml: LinkhutWeb.ErrorXML],
    layout: false
  ],
  pubsub_server: Linkhut.PubSub,
  live_view: [signing_salt: "b58amlvXfHSJ+dhn5yTMgbiMwJubVUHf"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Filter out sensitive parameters
config :phoenix, :filter_parameters, ["auth_token"]

config :mime, :types, %{
  "application/xml" => ["xml"]
}

config :phoenix_copy,
  default: [
    source: Path.expand("../assets/static/", __DIR__),
    destination: Path.expand("../priv/static/", __DIR__)
  ]

config :dart_sass,
  version: "1.77.8",
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

config :linkhut, Linkhut.Mail.Mailer, adapter: Swoosh.Adapters.Local

# Oban configuration
config :linkhut, Oban,
  engine: Oban.Engines.Basic,
  queues: [default: 10, mailer: 5, archiver: 5, crawler: 5],
  repo: Linkhut.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Reindexer, schedule: "@weekly"},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(60)}
  ],
  crontab: [
    # Every 2 minutes — fill archiver queue
    {"*/2 * * * *", Linkhut.Archiving.Workers.ArchiveScheduler},
    # Hourly — clean up orphaned pending_deletion snapshots
    {"0 * * * *", Linkhut.Archiving.Workers.StorageCleaner},
    # Every 15 minutes — mark stale snapshots as failed
    {"*/15 * * * *", Linkhut.Archiving.Workers.StaleSnapshotSweeper},
    # Daily at 3am — reconcile links with uncovered sources
    {"0 3 * * *", Linkhut.Archiving.Workers.Reconciler}
  ]

# Archiving configuration
config :linkhut, Linkhut.Archiving,
  mode: :disabled,
  max_file_size: 70_000_000,
  # serve_host: Dedicated hostname for serving archived content (e.g. "archive.example.com").
  # STRONGLY RECOMMENDED for self-hosters: without this, archived HTML is served
  # from the same origin as the main application, requiring a restrictive CSP
  # that may break archived page rendering. Set this to a separate subdomain.
  crawlers: [
    Linkhut.Archiving.Crawler.SingleFile,
    Linkhut.Archiving.Crawler.HttpFetch,
    Linkhut.Archiving.Crawler.WaybackMachine
  ],
  direct_file: [
    allowed_types: ["application/pdf", "text/plain", "application/json"]
  ],
  # Appended to crawler User-Agent. Recommended: a URL where site owners
  # can report issues or request opt-out, e.g. "+https://your-instance.com"
  user_agent_suffix: nil

config :linkhut, Linkhut.Archiving.Storage.Local, compression: :gzip

# Mail configuration
config :linkhut, Linkhut.Mail, sender: nil

# Moderation
config :linkhut, Linkhut.Moderation, account_age_days: 30

# Prometheus metrics endpoint
config :linkhut, Linkhut.Prometheus,
  username: nil,
  password: nil

# IFTTT integration
config :linkhut, Linkhut.IFTTT,
  user_id: 0,
  application: "",
  service_key: ""

# Single File configuration
config :single_file,
  version: "2.0.75",
  default: [
    args: []
  ]

# Rate limiting (Hammer)
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
