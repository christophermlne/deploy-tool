defmodule Deploy.Repo do
  use Ecto.Repo,
    otp_app: :deploy,
    adapter: Ecto.Adapters.SQLite3
end
