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
        nil -> [preload: [:steps]]
        status -> [status: status, preload: [:steps]]
      end

    deployments = Deployments.list_deployments(opts)
    assign(socket, deployments: deployments)
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
end
