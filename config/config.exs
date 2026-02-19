import Config

config :deploy, ecto_repos: [Deploy.Repo]

config :deploy, Deploy.Repo,
  database: Path.expand("../deploy.db", __DIR__),
  pool_size: 5

# Phoenix endpoint configuration
config :deploy, DeployWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DeployWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Deploy.PubSub,
  live_view: [signing_salt: "deploy_lv_salt"]

# Esbuild configuration
config :esbuild,
  version: "0.17.11",
  deploy: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Tailwind configuration
config :tailwind,
  version: "3.4.0",
  deploy: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
