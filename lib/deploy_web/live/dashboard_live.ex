defmodule DeployWeb.DashboardLive do
  @moduledoc """
  Dashboard showing recent and active deployments.
  """

  use DeployWeb, :live_view

  alias Deploy.Deployments
  alias Deploy.Deployments.Events

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Events.subscribe_all()
    end

    {:ok, load_deployments(socket)}
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

  # Ignore other events
  def handle_info(_event, socket), do: {:noreply, socket}

  defp load_deployments(socket) do
    recent = Deployments.list_deployments(limit: 10)
    active = Deployments.list_deployments(status: :in_progress)

    assign(socket,
      page_title: "Dashboard",
      recent_deployments: recent,
      active_deployments: active
    )
  end
end
