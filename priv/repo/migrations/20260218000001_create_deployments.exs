defmodule Deploy.Repo.Migrations.CreateDeployments do
  use Ecto.Migration

  def change do
    create table(:deployments) do
      add :deploy_date, :string, null: false
      add :pr_numbers, :string  # JSON array stored as string
      add :status, :string, null: false, default: "pending"
      add :current_phase, :string
      add :current_step, :string
      add :error_message, :text
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:deployments, [:deploy_date])
    create index(:deployments, [:status])
  end
end
