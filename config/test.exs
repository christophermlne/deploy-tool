import Config

# Use a separate test database
config :deploy, Deploy.Repo,
  database: Path.expand("../deploy_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox
