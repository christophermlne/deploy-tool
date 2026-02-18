defmodule Deploy.Deployments.DeploymentStep do
  @moduledoc """
  Schema for individual deployment steps.

  Each step belongs to a phase (setup, merge_prs, deploy_pr) and tracks:
  - Step name (e.g., create_workspace, clone_repo)
  - Status (pending, in_progress, completed, failed, skipped)
  - Timing information
  - Result or error details
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :pending | :in_progress | :completed | :failed | :skipped
  @type t :: %__MODULE__{}

  @statuses [:pending, :in_progress, :completed, :failed, :skipped]

  schema "deployment_steps" do
    field :phase, :string
    field :step_name, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :result, :map
    field :error, :string

    belongs_to :deployment, Deploy.Deployments.Deployment

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(phase step_name)a
  @optional_fields ~w(deployment_id status started_at completed_at result error)a

  @doc """
  Creates a changeset for a deployment step.
  """
  def changeset(step, attrs) do
    step
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:deployment_id)
  end

  @doc """
  Returns a changeset that marks the step as started.
  """
  def start_changeset(step) do
    changeset(step, %{
      status: :in_progress,
      started_at: DateTime.utc_now()
    })
  end

  @doc """
  Returns a changeset that marks the step as completed.
  """
  def complete_changeset(step, result \\ nil) do
    changeset(step, %{
      status: :completed,
      completed_at: DateTime.utc_now(),
      result: result
    })
  end

  @doc """
  Returns a changeset that marks the step as failed.
  """
  def fail_changeset(step, error) do
    changeset(step, %{
      status: :failed,
      completed_at: DateTime.utc_now(),
      error: error
    })
  end
end
