defmodule Linkhut.MixProject do
  use Mix.Project

  def project do
    [
      app: :linkhut,
      version: "0.1.0",
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      dialyzer: [plt_add_deps: :transitive],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "linkhut",
      source_url: "https://git.sr.ht/~mlb/linkhut",
      homepage_url: "https://git.sr.ht/~mlb/linkhut",
      docs: docs()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Linkhut.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:argon2_elixir, "~> 2.3"},
      {:atomex, "0.3.0"},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 0.5.0", only: [:dev], runtime: false},
      {:earmark, "~> 1.4"},
      {:ecto_sql, "~> 3.5"},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:ex_machina, "~> 2.4", only: :test},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.0"},
      {:phoenix, "~> 1.5.6"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_html, "~> 2.14"},
      {:phoenix_html_sanitizer, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.1"},
      {:phoenix_live_reload, "~> 1.3", only: :dev},
      {:phoenix_pubsub, "~> 2.0"},
      {:plug_cowboy, "~> 2.1"},
      {:postgrex, ">= 0.0.0"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_poller, "~> 0.4"},
      {:timex, "~> 3.6"},
      {:xml_builder, "~> 2.0.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end

  defp docs do
    [
      # The main page in the docs
      main: "readme",
      logo: "assets/static/images/favicon.svg",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      source_url_pattern: "https://git.sr.ht/~mlb/linkhut/tree/master/%{path}#L%{line}"
    ]
  end

  defp extras do
    [
      "README.md",

      "docs/api/overview.md",
      "docs/api/posts.md"
    ]
  end

  defp groups_for_extras do
    [
      "Introduction": "README.md",
      "External API": ~r/docs\/api\/.?/
    ]
  end
end
