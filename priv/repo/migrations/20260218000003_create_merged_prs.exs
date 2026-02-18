defmodule Deploy.Repo.Migrations.CreateMergedPrs do
  use Ecto.Migration

  def change do
    create table(:merged_prs) do
      add :deployment_id, references(:deployments, on_delete: :delete_all), null: false
      add :pr_number, :integer, null: false
      add :pr_title, :string, null: false
      add :merge_sha, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:merged_prs, [:deployment_id])
    create unique_index(:merged_prs, [:deployment_id, :pr_number])
  end
end
