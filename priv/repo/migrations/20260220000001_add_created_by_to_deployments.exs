defmodule Deploy.Repo.Migrations.AddCreatedByToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add :created_by_id, references(:users, on_delete: :nilify_all)
    end

    create index(:deployments, [:created_by_id])
  end
end
