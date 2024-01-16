defmodule Linkhut.MixProject do
  use Mix.Project

  def project do
    [
      app: :linkhut,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [] ++ Mix.compilers(),
      dialyzer: [plt_add_deps: :transitive],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # Docs
      name: "linkhut",
      source_url: "https://git.sr.ht/~mlb/linkhut",
      homepage_url: "https://git.sr.ht/~mlb/linkhut",
      docs: docs(),
      # Release
      releases: [
        linkhut: [
          steps: [:assemble, :tar]
        ]
      ]
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
      {:argon2_elixir, "~> 3.0"},
      {:atomex, "~> 0.5"},
      {:circular_buffer, "~> 0.4"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:phoenix_copy, "~> 0.1.1", runtime: Mix.env() == :dev},
      {:dart_sass, "~> 0.6", runtime: Mix.env() == :dev},
      {:dialyxir, "~> 1.2", only: [:dev], runtime: false},
      {:earmark, "~> 1.4"},
      {:ecto_sql, "~> 3.9"},
      {:ecto_psql_extras, "~> 0.7"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:ex_machina, "~> 2.7", only: :test},
      {:gettext, "~> 0.20"},
      {:gen_smtp, "~> 1.2"},
      {:jason, "~> 1.3"},
      {:phoenix, "~> 1.7"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 3.2"},
      {
        :phoenix_html_sanitizer,
        # pending https://github.com/elixirstatus/phoenix_html_sanitizer/pull/7
        git: "https://github.com/idyll/phoenix_html_sanitizer", branch: "elixir-1.15"
      },
      {:phoenix_live_dashboard, "~> 0.7"},
      {:phoenix_live_reload, "~> 1.3"},
      {:phoenix_live_view, "~> 0.18"},
      {
        :phoenix_oauth2_provider,
        # pending https://github.com/danschultzer/ex_oauth2_provider/pull/96
        git: "https://github.com/fastjames/phoenix_oauth2_provider", branch: "update_deps"
      },
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_view, "~> 2.0"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, ">= 0.0.0"},
      {:prom_ex, "~> 1.8.0"},
      {:swoosh, "~> 1.9"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:timex, "~> 3.7"},
      {:xml_builder, "~> 2.2"}
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
      "assets.deploy": [
        "phx.copy default",
        "sass default --no-source-map --style=compressed",
        "phx.digest"
      ],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end

  defp docs do
    [
      # The main page in the docs
      api_reference: false,
      main: "introduction",
      logo: "assets/static/images/favicon.svg",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      source_url_pattern: "https://git.sr.ht/~mlb/linkhut/tree/master/%{path}#L%{line}"
    ]
  end

  defp extras do
    [
      "docs/introduction/introduction.md",
      "docs/introduction/installation.md",
      "docs/api/overview.md",
      "docs/api/posts.md",
      "docs/api/tags.md"
    ]
  end

  defp groups_for_extras do
    [
      Introduction: ~r/docs\/introduction\/.?/,
      "External API": ~r/docs\/api\/.?/
    ]
  end
end
