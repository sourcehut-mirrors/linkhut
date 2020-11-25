use Mix.Config

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
config :logger, level: :warn
