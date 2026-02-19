defmodule DeployWeb.NewDeploymentLive do
  @moduledoc """
  LiveView for starting a new deployment.
  """

  use DeployWeb, :live_view

  alias Deploy.Deployments.Runner

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "New Deployment",
       pr_numbers_input: "",
       deploy_date: Deploy.Config.deploy_date(),
       skip_reviews: false,
       skip_ci: false,
       skip_conflicts: false,
       error: nil,
       submitting: false
     )}
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply,
     assign(socket,
       pr_numbers_input: params["pr_numbers"] || "",
       skip_reviews: params["skip_reviews"] == "true",
       skip_ci: params["skip_ci"] == "true",
       skip_conflicts: params["skip_conflicts"] == "true",
       error: nil
     )}
  end

  def handle_event("submit", params, socket) do
    require Logger
    Logger.info("Submit params: #{inspect(params)}")
    pr_numbers = parse_pr_numbers(params["pr_numbers"] || "")

    cond do
      pr_numbers == [] ->
        {:noreply, assign(socket, error: "Please enter at least one PR number")}

      socket.assigns.submitting ->
        {:noreply, socket}

      true ->
        socket = assign(socket, submitting: true, error: nil)

        opts = build_opts(pr_numbers, params)
        Logger.info("Built opts: #{inspect(opts)}")

        case Runner.start_deployment(opts) do
          {:ok, _pid, deployment} ->
            {:noreply,
             socket
             |> put_flash(:info, "Deployment started!")
             |> push_navigate(to: ~p"/deployments/#{deployment.id}")}

          {:error, {:deployment_exists, id}} ->
            {:noreply,
             socket
             |> assign(submitting: false, error: nil)
             |> put_flash(:error, "A deployment is already active")
             |> push_navigate(to: ~p"/deployments/#{id}")}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               submitting: false,
               error: "Failed to start deployment: #{inspect(reason)}"
             )}
        end
    end
  end

  defp parse_pr_numbers(input) do
    input
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.map(&parse_single_pr/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_single_pr(str) do
    # Handle formats like "123", "#123", "PR-123"
    str
    |> String.replace(~r/^[#PR-]+/i, "")
    |> Integer.parse()
    |> case do
      {num, ""} when num > 0 -> num
      _ -> nil
    end
  end

  defp build_opts(pr_numbers, params) do
    opts = [pr_numbers: pr_numbers]

    opts =
      if params["skip_reviews"] == "true",
        do: Keyword.put(opts, :skip_reviews, true),
        else: opts

    opts =
      if params["skip_ci"] == "true",
        do: Keyword.put(opts, :skip_ci, true),
        else: opts

    opts =
      if params["skip_conflicts"] == "true",
        do: Keyword.put(opts, :skip_conflicts, true),
        else: opts

    opts
  end
end
