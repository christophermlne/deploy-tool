defmodule Deploy.Deployments.Events do
  @moduledoc """
  PubSub event broadcasting for deployment progress.

  ## Event Types

  * `{:deployment_started, deployment_id}` - Deployment began
  * `{:deployment_completed, deployment_id, result}` - Deployment finished successfully
  * `{:deployment_failed, deployment_id, error}` - Deployment failed
  * `{:phase_started, deployment_id, phase}` - New phase began
  * `{:phase_completed, deployment_id, phase}` - Phase finished
  * `{:step_started, deployment_id, phase, step_name}` - Step execution began
  * `{:step_completed, deployment_id, phase, step_name, result}` - Step finished successfully
  * `{:step_failed, deployment_id, phase, step_name, error}` - Step failed
  * `{:pr_merged, deployment_id, pr_number, pr_title}` - PR was merged

  ## Subscribing

      Deploy.Deployments.Events.subscribe(deployment_id)

  Or subscribe to all deployments:

      Deploy.Deployments.Events.subscribe_all()
  """

  @pubsub Deploy.PubSub
  @topic_prefix "deployment"
  @global_topic "deployments:all"

  @type deployment_id :: integer()
  @type phase :: String.t()
  @type step_name :: String.t()

  @type event ::
          {:deployment_started, deployment_id()}
          | {:deployment_completed, deployment_id(), term()}
          | {:deployment_failed, deployment_id(), term()}
          | {:phase_started, deployment_id(), phase()}
          | {:phase_completed, deployment_id(), phase()}
          | {:step_started, deployment_id(), phase(), step_name()}
          | {:step_completed, deployment_id(), phase(), step_name(), term()}
          | {:step_failed, deployment_id(), phase(), step_name(), term()}
          | {:pr_merged, deployment_id(), integer(), String.t()}

  # ============================================================================
  # Subscription
  # ============================================================================

  @doc """
  Subscribe to events for a specific deployment.
  """
  @spec subscribe(deployment_id()) :: :ok | {:error, term()}
  def subscribe(deployment_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(deployment_id))
  end

  @doc """
  Unsubscribe from events for a specific deployment.
  """
  @spec unsubscribe(deployment_id()) :: :ok
  def unsubscribe(deployment_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(deployment_id))
  end

  @doc """
  Subscribe to events for all deployments.
  """
  @spec subscribe_all() :: :ok | {:error, term()}
  def subscribe_all do
    Phoenix.PubSub.subscribe(@pubsub, @global_topic)
  end

  @doc """
  Unsubscribe from events for all deployments.
  """
  @spec unsubscribe_all() :: :ok
  def unsubscribe_all do
    Phoenix.PubSub.unsubscribe(@pubsub, @global_topic)
  end

  # ============================================================================
  # Broadcasting
  # ============================================================================

  @doc """
  Broadcast an event to subscribers.
  """
  @spec broadcast(event()) :: :ok | {:error, term()}
  def broadcast(event) do
    deployment_id = extract_deployment_id(event)

    # Broadcast to specific deployment topic
    Phoenix.PubSub.broadcast(@pubsub, topic(deployment_id), event)

    # Also broadcast to global topic
    Phoenix.PubSub.broadcast(@pubsub, @global_topic, event)
  end

  @doc """
  Broadcast that a deployment has started.
  """
  @spec broadcast_deployment_started(deployment_id()) :: :ok | {:error, term()}
  def broadcast_deployment_started(deployment_id) do
    broadcast({:deployment_started, deployment_id})
  end

  @doc """
  Broadcast that a deployment has completed successfully.
  """
  @spec broadcast_deployment_completed(deployment_id(), term()) :: :ok | {:error, term()}
  def broadcast_deployment_completed(deployment_id, result) do
    broadcast({:deployment_completed, deployment_id, result})
  end

  @doc """
  Broadcast that a deployment has failed.
  """
  @spec broadcast_deployment_failed(deployment_id(), term()) :: :ok | {:error, term()}
  def broadcast_deployment_failed(deployment_id, error) do
    broadcast({:deployment_failed, deployment_id, error})
  end

  @doc """
  Broadcast that a phase has started.
  """
  @spec broadcast_phase_started(deployment_id(), phase()) :: :ok | {:error, term()}
  def broadcast_phase_started(deployment_id, phase) do
    broadcast({:phase_started, deployment_id, phase})
  end

  @doc """
  Broadcast that a phase has completed.
  """
  @spec broadcast_phase_completed(deployment_id(), phase()) :: :ok | {:error, term()}
  def broadcast_phase_completed(deployment_id, phase) do
    broadcast({:phase_completed, deployment_id, phase})
  end

  @doc """
  Broadcast that a step has started.
  """
  @spec broadcast_step_started(deployment_id(), phase(), step_name()) :: :ok | {:error, term()}
  def broadcast_step_started(deployment_id, phase, step_name) do
    broadcast({:step_started, deployment_id, phase, step_name})
  end

  @doc """
  Broadcast that a step has completed.
  """
  @spec broadcast_step_completed(deployment_id(), phase(), step_name(), term()) :: :ok | {:error, term()}
  def broadcast_step_completed(deployment_id, phase, step_name, result) do
    broadcast({:step_completed, deployment_id, phase, step_name, result})
  end

  @doc """
  Broadcast that a step has failed.
  """
  @spec broadcast_step_failed(deployment_id(), phase(), step_name(), term()) :: :ok | {:error, term()}
  def broadcast_step_failed(deployment_id, phase, step_name, error) do
    broadcast({:step_failed, deployment_id, phase, step_name, error})
  end

  @doc """
  Broadcast that a PR has been merged.
  """
  @spec broadcast_pr_merged(deployment_id(), integer(), String.t()) :: :ok | {:error, term()}
  def broadcast_pr_merged(deployment_id, pr_number, pr_title) do
    broadcast({:pr_merged, deployment_id, pr_number, pr_title})
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp topic(deployment_id), do: "#{@topic_prefix}:#{deployment_id}"

  defp extract_deployment_id({_event_type, deployment_id}), do: deployment_id
  defp extract_deployment_id({_event_type, deployment_id, _}), do: deployment_id
  defp extract_deployment_id({_event_type, deployment_id, _, _}), do: deployment_id
  defp extract_deployment_id({_event_type, deployment_id, _, _, _}), do: deployment_id
end
