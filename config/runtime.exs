import Config

if db_path = System.get_env("DATABASE_PATH") do
  config :deploy, Deploy.Repo, database: db_path
end
