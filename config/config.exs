import Config

config :deploy, ecto_repos: [Deploy.Repo]

config :deploy, Deploy.Repo,
  database: Path.expand("../deploy.db", __DIR__),
  pool_size: 5

# Import environment specific config
import_config "#{config_env()}.exs"
