defmodule Linkhut.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    validate_crawlers!()

    # List all child processes to be supervised
    children = [
      # Start the PromEx module
      Linkhut.PromEx,
      # Start the PubSub system
      {Phoenix.PubSub, name: Linkhut.PubSub},
      # Start the Ecto repository
      Linkhut.Repo,
      # Start the telemetry module
      LinkhutWeb.Telemetry,
      # Start genserver to store transient metrics
      {LinkhutWeb.MetricsStorage, LinkhutWeb.Telemetry.metrics()},
      # Start the endpoint when the application starts
      LinkhutWeb.Endpoint,
      # Starts a worker by calling: Linkhut.Worker.start_link(arg)
      # {Linkhut.Worker, arg},
      {Oban, Application.fetch_env!(:linkhut, Oban)}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Linkhut.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp validate_crawlers! do
    for module <- Linkhut.Config.archiving(:crawlers, []) do
      Code.ensure_loaded!(module)

      unless function_exported?(module, :type, 0) and
               function_exported?(module, :can_handle?, 2) and
               function_exported?(module, :fetch, 1) do
        raise "#{inspect(module)} does not implement Linkhut.Archiving.Crawler behaviour"
      end
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    LinkhutWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
