defmodule Deploy.MixProject do
  use Mix.Project

  def project do
    [
      app: :deploy,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Deploy.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Saga orchestrator from Ash
      {:reactor, "~> 1.0"},

      # HTTP client
      {:req, "~> 0.5"},

      # JSON parsing (usually included with Req, but explicit is good)
      {:jason, "~> 1.4"},

      # For Slack webhooks
      {:httpoison, "~> 2.0"},

      # Database
      {:ecto_sql, "~> 3.11"},
      {:ecto_sqlite3, "~> 0.17"},

      # PubSub for event broadcasting
      {:phoenix_pubsub, "~> 2.1"},

      {:plug, "~> 1.0", only: :test},

      # For development/testing
      # {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:mox, "~> 1.0", only: :test},

      {:igniter, "~> 0.6", only: [:dev, :test]}

      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
