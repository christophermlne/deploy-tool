defmodule Deploy.Repo.Migrations.AddSkipOptionsToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add :skip_reviews, :boolean, default: false, null: false
      add :skip_ci, :boolean, default: false, null: false
      add :skip_conflicts, :boolean, default: false, null: false
    end
  end
end
