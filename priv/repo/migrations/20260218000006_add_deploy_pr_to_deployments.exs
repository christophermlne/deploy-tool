defmodule Deploy.Repo.Migrations.AddDeployPrToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add :deploy_pr_number, :integer
      add :deploy_pr_url, :string
    end
  end
end
