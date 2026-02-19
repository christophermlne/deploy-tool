defmodule DeployWeb.DeploymentListLive do
  @moduledoc """
  LiveView for listing all deployments with filtering.
  """

  use DeployWeb, :live_view

  alias Deploy.Deployments
  alias Deploy.Deployments.Events

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Events.subscribe_all()
    end

    {:ok,
     socket
     |> assign(page_title: "Deployment History", status_filter: nil)
     |> load_deployments()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status_filter =
      case params["status"] do
        "pending" -> :pending
        "in_progress" -> :in_progress
        "completed" -> :completed
        "failed" -> :failed
        "cancelled" -> :cancelled
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(status_filter: status_filter)
     |> load_deployments()}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    path =
      if status == "" do
        ~p"/deployments"
      else
        ~p"/deployments?status=#{status}"
      end

    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_info({:deployment_started, _id}, socket) do
    {:noreply, load_deployments(socket)}
  end

  def handle_info({:deployment_completed, _id, _result}, socket) do
    {:noreply, load_deployments(socket)}
  end

  def handle_info({:deployment_failed, _id, _error}, socket) do
    {:noreply, load_deployments(socket)}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp load_deployments(socket) do
    opts =
      case socket.assigns.status_filter do
        nil -> []
        status -> [status: status]
      end

    deployments = Deployments.list_deployments(opts)
    assign(socket, deployments: deployments)
  end

  defp status_badge(status) do
    case status do
      :pending -> {"Pending", "bg-yellow-100 text-yellow-800"}
      :in_progress -> {"In Progress", "bg-blue-100 text-blue-800"}
      :completed -> {"Completed", "bg-green-100 text-green-800"}
      :failed -> {"Failed", "bg-red-100 text-red-800"}
      :cancelled -> {"Cancelled", "bg-gray-100 text-gray-800"}
      _ -> {"Unknown", "bg-gray-100 text-gray-800"}
    end
  end

  defp status_options do
    [
      {"All", ""},
      {"Pending", "pending"},
      {"In Progress", "in_progress"},
      {"Completed", "completed"},
      {"Failed", "failed"},
      {"Cancelled", "cancelled"}
    ]
  end

  defp format_duration(deployment) do
    case {deployment.started_at, deployment.completed_at} do
      {nil, _} -> "-"
      {started, nil} ->
        # Still running, show elapsed time
        seconds = DateTime.diff(DateTime.utc_now(), started)
        format_seconds(seconds) <> " (running)"
      {started, completed} ->
        seconds = DateTime.diff(completed, started)
        format_seconds(seconds)
    end
  end

  defp format_seconds(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_seconds(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end
  defp format_seconds(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end

  defp pr_url(pr_number) do
    owner = Deploy.Config.github_owner()
    repo = Deploy.Config.github_repo()
    "https://github.com/#{owner}/#{repo}/pull/#{pr_number}"
  end
end
