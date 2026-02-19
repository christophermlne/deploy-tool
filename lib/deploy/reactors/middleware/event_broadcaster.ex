defmodule Deploy.Reactors.Middleware.EventBroadcaster do
  @moduledoc """
  Reactor middleware that broadcasts step events via PubSub.

  Maps Reactor's internal events to deployment-specific events and broadcasts
  them through Deploy.Deployments.Events.

  ## Usage

  Add to a reactor via the middleware DSL:

      defmodule MyReactor do
        use Reactor

        middlewares do
          middleware Deploy.Reactors.Middleware.EventBroadcaster
        end
      end

  The reactor must be run with context containing `deployment_id` and `current_phase`:

      Reactor.run(MyReactor, inputs, %{
        deployment_id: 123,
        current_phase: "setup"
      })

  ## Event Mapping

  | Reactor Event          | Deployment Event                          |
  |------------------------|-------------------------------------------|
  | {:run_start, args}     | {:step_started, id, phase, step_name}     |
  | {:run_complete, result}| {:step_completed, id, phase, step, result}|
  | {:run_error, error}    | {:step_failed, id, phase, step, error}    |
  """

  use Reactor.Middleware
  require Logger

  alias Deploy.Deployments
  alias Deploy.Deployments.Events

  @impl true
  def init(context) do
    # Extract deployment_id from context if present
    # If not present, we're running standalone (CLI mode)
    {:ok, context}
  end

  @impl true
  def event({:run_start, _arguments}, step, context) do
    step_name = step_name_to_string(step.name)

    with {:ok, deployment_id, phase} <- extract_context(context, step_name) do
      # Create or update step record
      ensure_step_record(deployment_id, phase, step_name)

      # Update deployment's current step
      update_current_step(deployment_id, phase, step_name)

      # Broadcast event
      Events.broadcast_step_started(deployment_id, phase, step_name)

      Logger.debug("Step started: #{phase}/#{step_name}")
    end

    :ok
  end

  def event({:run_complete, result}, step, context) do
    step_name = step_name_to_string(step.name)

    with {:ok, deployment_id, phase} <- extract_context(context, step_name) do
      # Update step record
      complete_step_record(deployment_id, phase, step_name, result)

      # Handle special case: PR merged
      maybe_record_merged_prs(deployment_id, step_name, result)

      # Broadcast event
      Events.broadcast_step_completed(deployment_id, phase, step_name, result)

      Logger.debug("Step completed: #{phase}/#{step_name}")
    end

    :ok
  end

  def event({:run_error, errors}, step, context) do
    step_name = step_name_to_string(step.name)

    with {:ok, deployment_id, phase} <- extract_context(context, step_name) do
      error_message = format_errors(errors)

      # Update step record
      fail_step_record(deployment_id, phase, step_name, error_message)

      # Broadcast event
      Events.broadcast_step_failed(deployment_id, phase, step_name, errors)

      Logger.debug("Step failed: #{phase}/#{step_name} - #{error_message}")
    end

    :ok
  end

  # Handle other events we don't care about
  def event(_event, _step, _context), do: :ok

  @impl true
  def complete(result, context) do
    with {:ok, deployment_id, phase} <- extract_phase_context(context) do
      Events.broadcast_phase_completed(deployment_id, phase)
    end

    {:ok, result}
  end

  @impl true
  def error(errors, context) do
    with {:ok, deployment_id, phase} <- extract_phase_context(context) do
      Logger.error("Phase #{phase} failed for deployment #{deployment_id}: #{inspect(errors)}")
    end

    :ok
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Extract context with step-to-phase mapping lookup
  defp extract_context(context, step_name) do
    case {Map.get(context, :deployment_id), Map.get(context, :current_phase)} do
      {nil, _} ->
        :skip

      {_, nil} ->
        :skip

      {deployment_id, current_phase} ->
        # Look up the actual phase from step mapping if available
        phase =
          case Map.get(context, :step_to_phase) do
            nil -> current_phase
            mapping -> Map.get(mapping, step_name, current_phase)
          end

        {:ok, deployment_id, phase}
    end
  end

  # Extract context for phase-level callbacks (no step mapping lookup)
  defp extract_phase_context(context) do
    case {Map.get(context, :deployment_id), Map.get(context, :current_phase)} do
      {nil, _} -> :skip
      {_, nil} -> :skip
      {deployment_id, phase} -> {:ok, deployment_id, phase}
    end
  end

  # Convert step names to strings - handles atoms, strings, and tuples
  defp step_name_to_string(name) when is_atom(name), do: Atom.to_string(name)
  defp step_name_to_string(name) when is_binary(name), do: name
  defp step_name_to_string({:compose, name}), do: "compose_#{step_name_to_string(name)}"
  defp step_name_to_string(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&step_name_to_string/1)
    |> Enum.join("_")
  end
  defp step_name_to_string(other), do: inspect(other)

  defp ensure_step_record(deployment_id, phase, step_name) do
    deployment = Deployments.get_deployment!(deployment_id)

    case Deployments.get_step_by_name(deployment, phase, step_name) do
      nil ->
        Deployments.create_step(deployment, %{
          phase: phase,
          step_name: step_name,
          status: :in_progress,
          started_at: DateTime.utc_now()
        })

      step ->
        Deployments.start_step(step)
    end
  rescue
    e ->
      Logger.warning("Failed to create step record: #{inspect(e)}")
      :ok
  end

  defp complete_step_record(deployment_id, phase, step_name, result) do
    deployment = Deployments.get_deployment!(deployment_id)

    case Deployments.get_step_by_name(deployment, phase, step_name) do
      nil -> :ok
      step -> Deployments.complete_step(step, serialize_result(result))
    end
  rescue
    e ->
      Logger.warning("Failed to complete step record: #{inspect(e)}")
      :ok
  end

  defp fail_step_record(deployment_id, phase, step_name, error) do
    deployment = Deployments.get_deployment!(deployment_id)

    case Deployments.get_step_by_name(deployment, phase, step_name) do
      nil -> :ok
      step -> Deployments.fail_step(step, error)
    end
  rescue
    e ->
      Logger.warning("Failed to fail step record: #{inspect(e)}")
      :ok
  end

  defp update_current_step(deployment_id, phase, step_name) do
    deployment = Deployments.get_deployment!(deployment_id)

    Deployments.update_deployment(deployment, %{
      current_phase: phase,
      current_step: step_name
    })
  rescue
    e ->
      Logger.warning("Failed to update current step: #{inspect(e)}")
      :ok
  end

  # Handle the merge_prs step which returns a list of merged PRs
  defp maybe_record_merged_prs(deployment_id, "merge_prs", result) when is_list(result) do
    deployment = Deployments.get_deployment!(deployment_id)

    for pr <- result do
      pr_number = pr[:number] || pr["number"]
      pr_title = pr[:title] || pr["title"] || "PR ##{pr_number}"

      Deployments.record_merged_pr(deployment, %{
        pr_number: pr_number,
        pr_title: pr_title,
        merge_sha: pr[:sha] || pr["sha"]
      })

      Events.broadcast_pr_merged(deployment_id, pr_number, pr_title)
    end
  rescue
    e ->
      Logger.warning("Failed to record merged PRs: #{inspect(e)}")
      :ok
  end

  defp maybe_record_merged_prs(_, _, _), do: :ok

  defp serialize_result(result) when is_map(result) do
    # Convert to JSON-safe format
    result
    |> Jason.encode!()
    |> Jason.decode!()
  rescue
    _ -> %{"raw" => inspect(result)}
  end

  defp serialize_result(result) when is_list(result) do
    %{"items" => Enum.map(result, &serialize_result/1)}
  rescue
    _ -> %{"raw" => inspect(result)}
  end

  defp serialize_result(result), do: %{"value" => inspect(result)}

  defp format_errors(errors) when is_list(errors) do
    errors
    |> Enum.map(&Deploy.ErrorFormatter.format/1)
    |> Enum.join("; ")
  end

  defp format_errors(error), do: Deploy.ErrorFormatter.format(error)
end
