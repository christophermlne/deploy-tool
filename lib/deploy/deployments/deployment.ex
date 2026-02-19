defmodule Deploy.Deployments.Deployment do
  @moduledoc """
  Schema for deployment records.

  Tracks the overall state of a deployment including:
  - Which PRs are being deployed
  - Current phase and step
  - Status (pending, in_progress, completed, failed, cancelled)
  - Timestamps for when deployment started/completed
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :pending | :in_progress | :completed | :failed | :cancelled
  @type t :: %__MODULE__{}

  @statuses [:pending, :in_progress, :completed, :failed, :cancelled]

  schema "deployments" do
    field :deploy_date, :string
    field :pr_numbers, {:array, :integer}, default: []
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :current_phase, :string
    field :current_step, :string
    field :error_message, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    # Validation skip options
    field :skip_reviews, :boolean, default: false
    field :skip_ci, :boolean, default: false
    field :skip_conflicts, :boolean, default: false

    has_many :steps, Deploy.Deployments.DeploymentStep
    has_many :merged_prs, Deploy.Deployments.MergedPr

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(deploy_date)a
  @optional_fields ~w(pr_numbers status current_phase current_step error_message started_at completed_at skip_reviews skip_ci skip_conflicts)a

  @doc """
  Creates a changeset for a deployment.
  """
  def changeset(deployment, attrs) do
    deployment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Returns a changeset that marks the deployment as started.
  """
  def start_changeset(deployment) do
    changeset(deployment, %{
      status: :in_progress,
      started_at: DateTime.utc_now()
    })
  end

  @doc """
  Returns a changeset that marks the deployment as completed.
  """
  def complete_changeset(deployment) do
    changeset(deployment, %{
      status: :completed,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Returns a changeset that marks the deployment as failed.
  """
  def fail_changeset(deployment, error_message) do
    changeset(deployment, %{
      status: :failed,
      error_message: error_message,
      completed_at: DateTime.utc_now()
    })
  end
end
