defmodule DeployWeb.DeploymentShowLive do
  @moduledoc """
  LiveView for viewing a deployment with real-time updates.
  """

  use DeployWeb, :live_view

  alias Deploy.Deployments
  alias Deploy.Deployments.Events
  alias Deploy.Deployments.Registry
  alias Deploy.Deployments.Runner

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Deployments.get_deployment(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Deployment not found")
         |> push_navigate(to: ~p"/")}

      deployment ->
        deployment = Deployments.load_deployment_with_assocs(deployment)

        if connected?(socket) do
          Events.subscribe(deployment.id)
        end

        {:ok,
         assign(socket,
           page_title: "Deployment ##{deployment.id}",
           deployment: deployment,
           steps: deployment.steps,
           merged_prs: deployment.merged_prs,
           error: nil,
           is_active: Registry.is_active?(deployment.id)
         )}
    end
  end

  @impl true
  def handle_event("resume", _params, socket) do
    deployment = socket.assigns.deployment

    # Carry over skip options from the original deployment
    opts = [
      pr_numbers: deployment.pr_numbers,
      deploy_date: deployment.deploy_date,
      resume: true,
      skip_reviews: deployment.skip_reviews,
      skip_ci: deployment.skip_ci,
      skip_conflicts: deployment.skip_conflicts
    ]

    case Runner.start_deployment(opts) do
      {:ok, _pid, new_deployment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Deployment resumed!")
         |> push_navigate(to: ~p"/deployments/#{new_deployment.id}")}

      {:error, {:deployment_exists, existing_id}} ->
        {:noreply,
         socket
         |> put_flash(:error, "A deployment is already active")
         |> push_navigate(to: ~p"/deployments/#{existing_id}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(error: "Failed to resume: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel", _params, socket) do
    deployment = socket.assigns.deployment

    case Registry.lookup(deployment.id) do
      {:ok, pid} ->
        Runner.cancel(pid)

        {:noreply,
         socket
         |> put_flash(:info, "Deployment cancelled")}

      :error ->
        {:noreply,
         socket
         |> assign(error: "Deployment is not running")}
    end
  end

  @impl true
  def handle_info({:step_started, _id, phase, step_name}, socket) do
    steps = update_step_status(socket.assigns.steps, phase, step_name, :in_progress)
    {:noreply, assign(socket, steps: steps)}
  end

  def handle_info({:step_completed, _id, phase, step_name, _result}, socket) do
    steps = update_step_status(socket.assigns.steps, phase, step_name, :completed)
    {:noreply, assign(socket, steps: steps)}
  end

  def handle_info({:step_failed, _id, phase, step_name, error}, socket) do
    steps = update_step_status(socket.assigns.steps, phase, step_name, :failed)
    {:noreply, assign(socket, steps: steps, error: format_error(error))}
  end

  def handle_info({:pr_merged, _id, pr_number, pr_title}, socket) do
    new_pr = %{pr_number: pr_number, pr_title: pr_title}
    merged_prs = socket.assigns.merged_prs ++ [new_pr]
    {:noreply, assign(socket, merged_prs: merged_prs)}
  end

  def handle_info({:deployment_completed, _id, _result}, socket) do
    deployment = Deployments.get_deployment!(socket.assigns.deployment.id)
    deployment = Deployments.load_deployment_with_assocs(deployment)

    {:noreply,
     assign(socket,
       deployment: deployment,
       steps: deployment.steps,
       merged_prs: deployment.merged_prs,
       is_active: false
     )}
  end

  def handle_info({:deployment_failed, _id, error}, socket) do
    deployment = Deployments.get_deployment!(socket.assigns.deployment.id)
    deployment = Deployments.load_deployment_with_assocs(deployment)

    {:noreply,
     assign(socket,
       deployment: deployment,
       steps: deployment.steps,
       error: format_error(error),
       is_active: false
     )}
  end

  def handle_info({:deployment_started, _id}, socket) do
    {:noreply, assign(socket, is_active: true)}
  end

  def handle_info({:phase_started, _id, _phase}, socket), do: {:noreply, socket}
  def handle_info({:phase_completed, _id, _phase}, socket), do: {:noreply, socket}
  def handle_info(_event, socket), do: {:noreply, socket}

  defp update_step_status(steps, phase, step_name, status) do
    Enum.map(steps, fn step ->
      if step.phase == phase and step.step_name == step_name do
        %{step | status: status}
      else
        step
      end
    end)
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(:cancelled), do: "Deployment was cancelled"
  defp format_error(error), do: inspect(error)

  defp status_badge(status) do
    case status do
      :pending -> {"Pending", "bg-yellow-100 text-yellow-800"}
      :in_progress -> {"In Progress", "bg-blue-100 text-blue-800"}
      :completed -> {"Completed", "bg-green-100 text-green-800"}
      :failed -> {"Failed", "bg-red-100 text-red-800"}
      :cancelled -> {"Cancelled", "bg-gray-100 text-gray-800"}
      :skipped -> {"Skipped", "bg-gray-100 text-gray-600"}
      _ -> {"Unknown", "bg-gray-100 text-gray-800"}
    end
  end

  defp step_status_icon(status) do
    case status do
      :pending -> {"clock", "text-gray-400"}
      :in_progress -> {"arrow-path", "text-blue-500 animate-spin"}
      :completed -> {"check-circle", "text-green-500"}
      :failed -> {"x-circle", "text-red-500"}
      :skipped -> {"minus-circle", "text-gray-400"}
      _ -> {"question-mark-circle", "text-gray-400"}
    end
  end

  defp group_steps_by_phase(steps) do
    steps
    |> Enum.group_by(& &1.phase)
    |> Enum.sort_by(fn {phase, _} ->
      # Order phases: setup -> merge_prs -> deploy_pr
      case phase do
        "setup" -> 0
        "merge_prs" -> 1
        "deploy_pr" -> 2
        _ -> 3
      end
    end)
  end

  defp phase_display_name(phase) do
    case phase do
      "setup" -> "Setup"
      "merge_prs" -> "Merge PRs"
      "deploy_pr" -> "Create Deploy PR"
      other -> String.capitalize(other)
    end
  end

  defp phase_status(steps) do
    cond do
      Enum.any?(steps, &(&1.status == :failed)) -> :failed
      Enum.all?(steps, &(&1.status == :completed)) -> :completed
      Enum.any?(steps, &(&1.status == :in_progress)) -> :in_progress
      true -> :pending
    end
  end

  defp pr_url(pr_number) do
    owner = Deploy.Config.github_owner()
    repo = Deploy.Config.github_repo()
    "https://github.com/#{owner}/#{repo}/pull/#{pr_number}"
  end
end
