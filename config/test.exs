import Config

# Configure your database
config :linkhut, Linkhut.Repo,
  username: "postgres",
  password: "postgres",
  database: "linkhut_test",
  hostname: "localhost",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :linkhut, LinkhutWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :linkhut, Linkhut.Mail, sender: {"linkhut", "no-reply@example.com"}

config :linkhut, Linkhut.IFTTT,
  user_id: 0,
  application: "a2ac2720c90e458752257e5acdc5cace7c1667e835fd833df3268f5d5bc3067b",
  service_key: "cccddd"

config :linkhut, Linkhut.Archiving,
  mode: :limited,
  data_dir: Path.join(System.tmp_dir!(), "linkhut_test_archives"),
  serve_host: nil,
  storage: Linkhut.Archiving.Storage.Local

config :linkhut, Linkhut.Archiving.Storage.Local, compression: :gzip

# Disable SSL requirement for redirect URIs in tests
config :linkhut, ExOauth2Provider, force_ssl_in_redirect_uri: false

# Mailer configuration
config :linkhut, Linkhut.Mail.Mailer, adapter: Swoosh.Adapters.Test

# Oban configuration
config :linkhut, Oban, testing: :manual

# Req configuration
config :linkhut,
  req_options: [
    plug: {Req.Test, Linkhut.Links.Link}
  ],
  wayback_req_options: [
    plug: {Req.Test, Linkhut.Archiving.Crawler.WaybackMachine}
  ]
