defmodule Deploy.Deployments.Runner do
  @moduledoc """
  GenServer that wraps a single deployment execution.

  Coordinates between:
  - The existing Deploy.Runner module (Reactor execution)
  - The database (via Deploy.Deployments context)
  - The event system (via Deploy.Deployments.Events)
  - The registry (via Deploy.Deployments.Registry)

  ## Starting a Deployment

      {:ok, pid} = Deploy.Deployments.Supervisor.start_runner(
        deployment_id: 123,
        pr_numbers: [12, 13],
        opts: [skip_validation: true]
      )

  Or use the convenience function:

      {:ok, pid, deployment} = Deploy.Deployments.Runner.start_deployment(
        pr_numbers: [12, 13],
        deploy_date: "20260218"
      )
  """

  use GenServer, restart: :temporary
  require Logger

  alias Deploy.Deployments
  alias Deploy.Deployments.Events

  @type state :: %{
          deployment_id: integer(),
          deployment: Deployments.Deployment.t(),
          status: :initializing | :running | :completed | :failed,
          task: Task.t() | nil,
          opts: keyword()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Starts a new deployment, creating the database record and runner process.

  Returns `{:ok, pid, deployment}` on success.

  ## Options
    - `:pr_numbers` - list of PR numbers to merge (required)
    - `:deploy_date` - deploy date (defaults to today)
    - Other options are passed to Deploy.Runner.deploy_pr/1
  """
  @spec start_deployment(keyword()) :: {:ok, pid(), Deployments.Deployment.t()} | {:error, term()}
  def start_deployment(opts) do
    pr_numbers = Keyword.fetch!(opts, :pr_numbers)
    deploy_date = Keyword.get(opts, :deploy_date, Deploy.Config.deploy_date())

    # Extract skip options
    skip_reviews = Keyword.get(opts, :skip_reviews, false)
    skip_ci = Keyword.get(opts, :skip_ci, false)
    skip_conflicts = Keyword.get(opts, :skip_conflicts, false)

    # Check for existing active deployment
    case Deployments.get_active_deployment(deploy_date) do
      %Deployments.Deployment{} = existing ->
        {:error, {:deployment_exists, existing.id}}

      nil ->
        # Create the deployment record with skip options
        deployment_attrs = %{
          deploy_date: deploy_date,
          pr_numbers: pr_numbers,
          status: :pending,
          skip_reviews: skip_reviews,
          skip_ci: skip_ci,
          skip_conflicts: skip_conflicts
        }

        case Deployments.create_deployment(deployment_attrs) do
          {:ok, deployment} ->
            # Start the runner process - pass skip options from deployment record
            runner_opts = [
              deployment_id: deployment.id,
              pr_numbers: pr_numbers,
              deploy_date: deploy_date,
              runner_opts: [
                resume: Keyword.get(opts, :resume, false),
                skip_reviews: deployment.skip_reviews,
                skip_ci: deployment.skip_ci,
                skip_conflicts: deployment.skip_conflicts
              ]
            ]

            case Deployments.Supervisor.start_runner(runner_opts) do
              {:ok, pid} -> {:ok, pid, deployment}
              error -> error
            end

          {:error, changeset} ->
            {:error, {:database_error, changeset}}
        end
    end
  end

  @doc """
  Gets the current status of a running deployment.
  """
  @spec get_status(pid()) :: {:ok, map()} | {:error, term()}
  def get_status(pid) do
    GenServer.call(pid, :get_status)
  end

  @doc """
  Cancels a running deployment.
  """
  @spec cancel(pid()) :: :ok | {:error, term()}
  def cancel(pid) do
    GenServer.call(pid, :cancel)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    deployment_id = Keyword.fetch!(opts, :deployment_id)
    pr_numbers = Keyword.fetch!(opts, :pr_numbers)
    deploy_date = Keyword.get(opts, :deploy_date, Deploy.Config.deploy_date())
    runner_opts = Keyword.get(opts, :runner_opts, [])

    # Register ourselves
    case Deployments.Registry.register(deployment_id) do
      :ok ->
        # Load the deployment
        deployment = Deployments.get_deployment!(deployment_id)

        state = %{
          deployment_id: deployment_id,
          deployment: deployment,
          status: :initializing,
          task: nil,
          opts: Keyword.merge(runner_opts, pr_numbers: pr_numbers, deploy_date: deploy_date)
        }

        # Schedule the deployment to start
        send(self(), :start_deployment)

        {:ok, state}

      {:error, :already_registered} ->
        {:stop, :already_running}
    end
  end

  @impl true
  def handle_info(:start_deployment, state) do
    # Update deployment status
    {:ok, deployment} = Deployments.start_deployment(state.deployment)
    Events.broadcast_deployment_started(state.deployment_id)

    # Build opts for Deploy.Runner with deployment_id for middleware
    opts =
      state.opts
      |> Keyword.put(:deployment_id, state.deployment_id)

    # Start the deployment in a Task
    task = Task.async(fn -> run_deployment(opts) end)

    {:noreply, %{state | status: :running, deployment: deployment, task: task}}
  end

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    # Task completed - clean up the monitor
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, deploy_result} ->
        {:ok, deployment} = Deployments.complete_deployment(state.deployment)

        # Store deploy PR number if available
        {:ok, deployment} =
          Deployments.update_deployment(deployment, %{
            deploy_pr_number: deploy_result[:pr_number]
          })

        Events.broadcast_deployment_completed(state.deployment_id, deploy_result)

        {:stop, :normal, %{state | status: :completed, deployment: deployment, task: nil}}

      {:error, error} ->
        error_message = format_error(error)
        {:ok, deployment} = Deployments.fail_deployment(state.deployment, error_message)
        Events.broadcast_deployment_failed(state.deployment_id, error)

        {:stop, :normal, %{state | status: :failed, deployment: deployment, task: nil}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    # Task crashed
    error_message = "Deployment task crashed: #{inspect(reason)}"
    {:ok, deployment} = Deployments.fail_deployment(state.deployment, error_message)
    Events.broadcast_deployment_failed(state.deployment_id, reason)

    {:stop, :normal, %{state | status: :failed, deployment: deployment, task: nil}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      deployment_id: state.deployment_id,
      status: state.status,
      deployment: state.deployment
    }

    {:reply, {:ok, status}, state}
  end

  def handle_call(:cancel, _from, %{task: task} = state) when not is_nil(task) do
    Task.shutdown(task, :brutal_kill)

    {:ok, deployment} = Deployments.fail_deployment(state.deployment, "Cancelled by user")
    Events.broadcast_deployment_failed(state.deployment_id, :cancelled)

    {:stop, :normal, :ok, %{state | status: :failed, deployment: deployment, task: nil}}
  end

  def handle_call(:cancel, _from, state) do
    {:reply, {:error, :not_running}, state}
  end

  @impl true
  def terminate(_reason, state) do
    Deployments.Registry.unregister(state.deployment_id)
    :ok
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp run_deployment(opts) do
    # Delegate to the existing Deploy.Runner module
    # The EventBroadcaster middleware will handle step-level events
    Deploy.Runner.deploy_pr(opts)
  end

  defp format_error(error), do: Deploy.ErrorFormatter.format(error)
end
