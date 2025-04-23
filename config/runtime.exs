import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/linkhut start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :linkhut, LinkhutWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6"), do: [:inet6], else: []

  config :linkhut, Linkhut.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  port = String.to_integer(System.get_env("PORT") || "4000")

  config :linkhut, LinkhutWeb.Endpoint,
    server: true,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 1},
      port: port
    ],
    secret_key_base: secret_key_base

  # Mailer config:
  maybe_dkim_config =
    if dkim_selector = System.get_env("SMTP_DKIM_SELECTOR") != nil do
      [
        dkim: [
          s: dkim_selector,
          d: System.get_env("SMTP_DKIM_DOMAIN"),
          private_key:
            {:pem_plain, File.read!(System.get_env("SMTP_DKIM_PRIVATE_KEY") || "/dev/null")}
        ]
      ]
    else
      []
    end

  config :linkhut,
         Linkhut.Mailer,
         [
           adapter: Swoosh.Adapters.SMTP,
           relay: System.get_env("SMTP_HOST"),
           username: System.get_env("SMTP_USERNAME"),
           password: System.get_env("SMTP_PASSWORD"),
           ssl: false,
           tls: :always,
           tls_options: [verify: :verify_none],
           auth: :always,
           port: System.get_env("SMTP_PORT"),
           retries: 2,
           no_mx_lookups: false
         ] ++ maybe_dkim_config

  config :linkhut, Linkhut,
    mail: [
      sender: {System.get_env("EMAIL_FROM_NAME"), System.get_env("EMAIL_FROM_ADDRESS")}
    ],
    prometheus: [
      username: System.get_env("PROMETHEUS_USERNAME"),
      password: System.get_env("PROMETHEUS_PASSWORD")
    ],
    # IFTTT config
    ifttt: [
      user_id: String.to_integer(System.get_env("IFTTT_USER_ID") || "0"),
      application: System.get_env("IFTTT_APPLICATION") || "",
      service_key: System.get_env("IFTTT_SERVICE_KEY") || ""
    ]
end
