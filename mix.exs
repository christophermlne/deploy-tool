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

      # Phoenix and LiveView
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.5"},

      # Authentication
      {:bcrypt_elixir, "~> 3.0"},

      # Assets (dev only)
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},

      # Plug is required by Phoenix, not just tests

      # For development/testing
      {:mox, "~> 1.0", only: :test},
      {:igniter, "~> 0.6", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind deploy", "esbuild deploy"],
      "assets.deploy": [
        "tailwind deploy --minify",
        "esbuild deploy --minify",
        "phx.digest"
      ]
    ]
  end
end
