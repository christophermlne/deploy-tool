defmodule Deploy.Reactors.Steps.ChangePRBases do
  @moduledoc """
  Retargets approved PRs from staging to the deploy branch.

  Compensation: changes base back to "staging" for each PR that was changed.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(%{client: client, owner: owner, repo: repo, prs: prs, deploy_branch: deploy_branch}, _context, _options) do

    prs
    |> Enum.reduce_while({:ok, []}, fn pr, {:ok, acc} ->
      case Deploy.GitHub.change_pr_base(client, owner, repo, pr.number, deploy_branch) do
        {:ok, _} ->
          Logger.info("Retargeted PR ##{pr.number} to #{deploy_branch}")
          {:cont, {:ok, [pr | acc]}}

        {:error, reason} ->
          {:halt, {:error, "Failed to change base for PR ##{pr.number}: #{inspect(reason)}"}}
      end
    end)
    |> then(fn
      {:ok, changed} -> {:ok, Enum.reverse(changed)}
      error -> error
    end)
  end

  @impl true
  def compensate(changed_prs, arguments, _context, _options) do
    client = arguments.client
    owner = arguments.owner
    repo = arguments.repo

    Enum.each(changed_prs, fn pr ->
      Logger.info("Compensating: retargeting PR ##{pr.number} back to staging")

      case Deploy.GitHub.change_pr_base(client, owner, repo, pr.number, "staging") do
        {:ok, _} -> :ok
        {:error, reason} ->
          Logger.warning("Failed to revert PR ##{pr.number} base: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
