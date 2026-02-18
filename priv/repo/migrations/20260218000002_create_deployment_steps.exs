defmodule Deploy.Repo.Migrations.CreateDeploymentSteps do
  use Ecto.Migration

  def change do
    create table(:deployment_steps) do
      add :deployment_id, references(:deployments, on_delete: :delete_all), null: false
      add :phase, :string, null: false
      add :step_name, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :result, :text  # JSON
      add :error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:deployment_steps, [:deployment_id])
    create index(:deployment_steps, [:deployment_id, :phase])
  end
end
