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

  host = System.get_env("LINKHUT_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # Configure IP binding based on environment variable
  # BIND_IP=public binds to all interfaces: {0, 0, 0, 0, 0, 0, 0, 0}
  # BIND_IP=loopback (or unset) binds to loopback only: {0, 0, 0, 0, 0, 0, 0, 1}
  ip_address =
    case System.get_env("BIND_IP") do
      "public" -> {0, 0, 0, 0, 0, 0, 0, 0}
      _ -> {0, 0, 0, 0, 0, 0, 0, 1}
    end

  config :linkhut, LinkhutWeb.Endpoint,
    url: [host: host, scheme: "https", port: 443],
    http: [
      ip: ip_address,
      port: port
    ],
    secret_key_base: secret_key_base

  # Mailer config:
  if smtp_host = System.get_env("SMTP_HOST") do
    smtp_username = System.get_env("SMTP_USERNAME")
    smtp_password = System.get_env("SMTP_PASSWORD")

    maybe_auth_config =
      cond do
        smtp_username && smtp_password ->
          [username: smtp_username, password: smtp_password, auth: :always]

        smtp_username || smtp_password ->
          Logger.warning(
            "Both SMTP_USERNAME and SMTP_PASSWORD must be set for SMTP authentication; falling back to unauthenticated mode"
          )

          [auth: :never]

        true ->
          [auth: :never]
      end

    smtp_tls =
      case System.get_env("SMTP_TLS") do
        "always" ->
          :always

        "never" ->
          :never

        "if_available" ->
          :if_available

        nil ->
          :if_available

        other ->
          raise "Invalid SMTP_TLS value: #{inspect(other)}. Expected \"always\", \"never\", or \"if_available\"."
      end

    unless System.get_env("EMAIL_FROM_ADDRESS") do
      raise "EMAIL_FROM_ADDRESS must be set when SMTP_HOST is configured"
    end

    maybe_dkim_config =
      if (dkim_selector = System.get_env("SMTP_DKIM_SELECTOR")) != nil do
        dkim_domain =
          System.get_env("SMTP_DKIM_DOMAIN") ||
            raise "SMTP_DKIM_DOMAIN must be set when SMTP_DKIM_SELECTOR is configured"

        dkim_private_key_path =
          System.get_env("SMTP_DKIM_PRIVATE_KEY") ||
            raise "SMTP_DKIM_PRIVATE_KEY must be set when SMTP_DKIM_SELECTOR is configured"

        dkim_private_key_pem =
          case File.read(dkim_private_key_path) do
            {:ok, contents} ->
              contents

            {:error, reason} ->
              raise "Cannot read DKIM private key at #{dkim_private_key_path}: #{:file.format_error(reason)}"
          end

        [
          dkim: [
            s: dkim_selector,
            d: dkim_domain,
            private_key: {:pem_plain, dkim_private_key_pem}
          ]
        ]
      else
        []
      end

    config :linkhut,
           Linkhut.Mail.Mailer,
           [
             adapter: Swoosh.Adapters.SMTP,
             relay: smtp_host,
             ssl: System.get_env("SMTP_SSL") == "true",
             tls: smtp_tls,
             # verify: :verify_none for compatibility with self-signed certificates
             # on internal SMTP servers common in self-hosted setups
             tls_options: [verify: :verify_none],
             port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
             retries: 2,
             no_mx_lookups: false
           ] ++ maybe_auth_config ++ maybe_dkim_config
  end

  # Mail -- only override sender if EMAIL_FROM_ADDRESS is set.
  if from_address = System.get_env("EMAIL_FROM_ADDRESS") do
    config :linkhut, Linkhut.Mail, sender: {System.get_env("EMAIL_FROM_NAME"), from_address}
  end

  # Prometheus
  prometheus_overrides =
    [
      username: System.get_env("PROMETHEUS_USERNAME"),
      password: System.get_env("PROMETHEUS_PASSWORD")
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)

  if prometheus_overrides != [] do
    config :linkhut, Linkhut.Prometheus, prometheus_overrides
  end

  # IFTTT
  ifttt_overrides =
    [
      user_id:
        case System.get_env("IFTTT_USER_ID") do
          nil -> nil
          val -> String.to_integer(val)
        end,
      application: System.get_env("IFTTT_APPLICATION"),
      service_key: System.get_env("IFTTT_SERVICE_KEY")
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)

  if ifttt_overrides != [] do
    config :linkhut, Linkhut.IFTTT, ifttt_overrides
  end

  # Archiving -- only override keys that have env var values.
  archiving_overrides =
    [
      data_dir: System.get_env("ARCHIVING_DATA_DIR"),
      serve_host: System.get_env("ARCHIVING_SERVE_HOST"),
      user_agent_suffix: System.get_env("ARCHIVING_USER_AGENT_SUFFIX"),
      mode:
        case System.get_env("ARCHIVING_MODE") do
          "enabled" -> :enabled
          "limited" -> :limited
          "disabled" -> :disabled
          _ -> nil
        end,
      max_file_size:
        case System.get_env("ARCHIVING_MAX_FILE_SIZE") do
          nil -> nil
          val -> String.to_integer(val)
        end
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)

  if archiving_overrides != [] do
    config :linkhut, Linkhut.Archiving, archiving_overrides
  end
end
