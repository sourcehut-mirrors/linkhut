defmodule SingleFile.MixProject do
  use Mix.Project

  def project do
    [
      app: :single_file,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [test: ["single_file.install --if-missing", "test"]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, inets: :optional, ssl: :optional],
      env: [default: []]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:castore, ">= 0.0.0"},
      {:ex_doc, ">= 0.0.0", only: :docs}
    ]
  end
end
