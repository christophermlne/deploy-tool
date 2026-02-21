defmodule DeployWeb.PRPopoverHook do
  @moduledoc """
  LiveView on_mount hook that handles PR popover data fetching.

  Attaches to all LiveViews via the router's live_session on_mount.
  Intercepts "fetch_pr_info" events from the JS PRPopover hook,
  fetches PR details from GitHub asynchronously, and pushes the
  result back to the client via push_event.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> attach_hook(:pr_popover_event, :handle_event, &handle_event/3)
      |> attach_hook(:pr_popover_async, :handle_async, &handle_async/3)

    {:cont, socket}
  end

  defp handle_event("fetch_pr_info", %{"pr_number" => pr_number}, socket) do
    pr_number = to_integer(pr_number)

    socket =
      start_async(socket, {:pr_info, pr_number}, fn ->
        client = Deploy.GitHub.client(Deploy.Config.github_token())
        owner = Deploy.Config.github_owner()
        repo = Deploy.Config.github_repo()

        Deploy.GitHub.get_pr_popover_info(client, owner, repo, pr_number)
      end)

    {:halt, socket}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_async({:pr_info, pr_number}, {:ok, {:ok, data}}, socket) do
    {:halt, push_event(socket, "pr_info", Map.put(data, :pr_number, pr_number))}
  end

  defp handle_async({:pr_info, pr_number}, {:ok, {:error, reason}}, socket) do
    {:halt, push_event(socket, "pr_info", %{pr_number: pr_number, error: inspect(reason)})}
  end

  defp handle_async({:pr_info, pr_number}, {:exit, reason}, socket) do
    {:halt, push_event(socket, "pr_info", %{pr_number: pr_number, error: inspect(reason)})}
  end

  defp handle_async(_name, _result, socket), do: {:cont, socket}

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
end
