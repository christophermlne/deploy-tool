defmodule Deploy.Deployments do
  @moduledoc """
  Context module for deployment state management.

  Provides CRUD operations for deployments and their associated steps/PRs.
  """

  import Ecto.Query
  alias Deploy.Repo
  alias Deploy.Deployments.{Deployment, DeploymentStep, MergedPr}

  # ============================================================================
  # Deployment CRUD
  # ============================================================================

  @doc """
  Creates a new deployment record.
  """
  @spec create_deployment(map()) :: {:ok, Deployment.t()} | {:error, Ecto.Changeset.t()}
  def create_deployment(attrs) do
    %Deployment{}
    |> Deployment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a deployment by ID.
  """
  @spec get_deployment(integer()) :: Deployment.t() | nil
  def get_deployment(id), do: Repo.get(Deployment, id)

  @doc """
  Gets a deployment by ID, raises if not found.
  """
  @spec get_deployment!(integer()) :: Deployment.t()
  def get_deployment!(id), do: Repo.get!(Deployment, id)

  @doc """
  Gets the most recent deployment for a given date.
  """
  @spec get_deployment_by_date(String.t()) :: Deployment.t() | nil
  def get_deployment_by_date(deploy_date) do
    Deployment
    |> where(deploy_date: ^deploy_date)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets an active (pending or in_progress) deployment for a given date.
  """
  @spec get_active_deployment(String.t()) :: Deployment.t() | nil
  def get_active_deployment(deploy_date) do
    Deployment
    |> where(deploy_date: ^deploy_date)
    |> where([d], d.status in [:pending, :in_progress])
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Updates a deployment with the given attributes.
  """
  @spec update_deployment(Deployment.t(), map()) :: {:ok, Deployment.t()} | {:error, Ecto.Changeset.t()}
  def update_deployment(%Deployment{} = deployment, attrs) do
    deployment
    |> Deployment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a deployment as started (in_progress).
  """
  @spec start_deployment(Deployment.t()) :: {:ok, Deployment.t()} | {:error, Ecto.Changeset.t()}
  def start_deployment(%Deployment{} = deployment) do
    deployment
    |> Deployment.start_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a deployment as completed.
  """
  @spec complete_deployment(Deployment.t()) :: {:ok, Deployment.t()} | {:error, Ecto.Changeset.t()}
  def complete_deployment(%Deployment{} = deployment) do
    deployment
    |> Deployment.complete_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a deployment as failed with an error message.
  """
  @spec fail_deployment(Deployment.t(), String.t()) :: {:ok, Deployment.t()} | {:error, Ecto.Changeset.t()}
  def fail_deployment(%Deployment{} = deployment, error_message) do
    deployment
    |> Deployment.fail_changeset(error_message)
    |> Repo.update()
  end

  @doc """
  Lists deployments with optional filtering.

  ## Options
    - `:status` - filter by status
    - `:limit` - limit number of results
    - `:preload` - list of associations to preload (e.g., `[:steps]`)
  """
  @spec list_deployments(keyword()) :: [Deployment.t()]
  def list_deployments(opts \\ []) do
    Deployment
    |> maybe_filter_status(opts[:status])
    |> order_by(desc: :inserted_at)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
    |> maybe_preload(opts[:preload])
  end

  @doc """
  Preloads steps and merged_prs associations for a deployment.
  """
  @spec load_deployment_with_assocs(Deployment.t()) :: Deployment.t()
  def load_deployment_with_assocs(%Deployment{} = deployment) do
    Repo.preload(deployment, [:steps, :merged_prs])
  end

  # ============================================================================
  # Deployment Steps
  # ============================================================================

  @doc """
  Creates a step record for a deployment.
  """
  @spec create_step(Deployment.t(), map()) :: {:ok, DeploymentStep.t()} | {:error, Ecto.Changeset.t()}
  def create_step(%Deployment{id: deployment_id}, attrs) do
    %DeploymentStep{}
    |> DeploymentStep.changeset(Map.put(attrs, :deployment_id, deployment_id))
    |> Repo.insert()
  end

  @doc """
  Gets a step by ID.
  """
  @spec get_step(integer()) :: DeploymentStep.t() | nil
  def get_step(id), do: Repo.get(DeploymentStep, id)

  @doc """
  Gets a step by deployment, phase, and step name.
  """
  @spec get_step_by_name(Deployment.t(), String.t(), String.t()) :: DeploymentStep.t() | nil
  def get_step_by_name(%Deployment{id: deployment_id}, phase, step_name) do
    DeploymentStep
    |> where(deployment_id: ^deployment_id, phase: ^phase, step_name: ^step_name)
    |> Repo.one()
  end

  @doc """
  Updates a step with the given attributes.
  """
  @spec update_step(DeploymentStep.t(), map()) :: {:ok, DeploymentStep.t()} | {:error, Ecto.Changeset.t()}
  def update_step(%DeploymentStep{} = step, attrs) do
    step
    |> DeploymentStep.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a step as started.
  """
  @spec start_step(DeploymentStep.t()) :: {:ok, DeploymentStep.t()} | {:error, Ecto.Changeset.t()}
  def start_step(%DeploymentStep{} = step) do
    step
    |> DeploymentStep.start_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a step as completed with an optional result.
  """
  @spec complete_step(DeploymentStep.t(), map() | nil) :: {:ok, DeploymentStep.t()} | {:error, Ecto.Changeset.t()}
  def complete_step(%DeploymentStep{} = step, result \\ nil) do
    step
    |> DeploymentStep.complete_changeset(result)
    |> Repo.update()
  end

  @doc """
  Marks a step as failed with an error message.
  """
  @spec fail_step(DeploymentStep.t(), String.t()) :: {:ok, DeploymentStep.t()} | {:error, Ecto.Changeset.t()}
  def fail_step(%DeploymentStep{} = step, error) do
    step
    |> DeploymentStep.fail_changeset(error)
    |> Repo.update()
  end

  @doc """
  Lists all steps for a deployment.
  """
  @spec list_steps(Deployment.t()) :: [DeploymentStep.t()]
  def list_steps(%Deployment{id: deployment_id}) do
    DeploymentStep
    |> where(deployment_id: ^deployment_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  # ============================================================================
  # Merged PRs
  # ============================================================================

  @doc """
  Records a merged PR for a deployment.
  """
  @spec record_merged_pr(Deployment.t(), map()) :: {:ok, MergedPr.t()} | {:error, Ecto.Changeset.t()}
  def record_merged_pr(%Deployment{id: deployment_id}, attrs) do
    %MergedPr{}
    |> MergedPr.changeset(Map.put(attrs, :deployment_id, deployment_id))
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc """
  Lists all merged PRs for a deployment.
  """
  @spec list_merged_prs(Deployment.t()) :: [MergedPr.t()]
  def list_merged_prs(%Deployment{id: deployment_id}) do
    MergedPr
    |> where(deployment_id: ^deployment_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp maybe_preload(deployments, nil), do: deployments
  defp maybe_preload(deployments, []), do: deployments
  defp maybe_preload(deployments, preloads), do: Repo.preload(deployments, preloads)
end
