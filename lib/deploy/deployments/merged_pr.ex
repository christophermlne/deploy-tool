defmodule Deploy.Deployments.MergedPr do
  @moduledoc """
  Schema for tracking PRs that were merged as part of a deployment.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "merged_prs" do
    field :pr_number, :integer
    field :pr_title, :string
    field :merge_sha, :string

    belongs_to :deployment, Deploy.Deployments.Deployment

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(pr_number pr_title)a
  @optional_fields ~w(deployment_id merge_sha)a

  @doc """
  Creates a changeset for a merged PR record.
  """
  def changeset(merged_pr, attrs) do
    merged_pr
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:deployment_id)
    |> unique_constraint([:deployment_id, :pr_number])
  end
end
