defmodule Deploy.Reactors.Steps.MergePRs do
  @moduledoc """
  Merges PRs sequentially via squash merge.

  This is a point of no return — compensation logs a warning but cannot undo merges.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(arguments, _context, _options) do
    client = arguments.client
    owner = arguments.owner
    repo = arguments.repo
    prs = arguments.prs

    Enum.reduce_while(prs, {:ok, []}, fn pr, {:ok, acc} ->
      with :ok <- maybe_update_branch(client, owner, repo, pr.number, acc),
           {:ok, body} <- Deploy.GitHub.merge_pr(client, owner, repo, pr.number) do
        merged = %{
          number: pr.number,
          title: pr.title,
          sha: body["sha"]
        }

        Logger.info("Merged PR ##{pr.number}: #{pr.title}")
        {:cont, {:ok, acc ++ [merged]}}
      else
        {:error, reason} ->
          {:halt, {:error, "Failed to merge PR ##{pr.number}: #{inspect(reason)}"}}
      end
    end)
  end

  # After the first merge, the base branch has changed so subsequent
  # PRs need their branches updated before they can merge.
  defp maybe_update_branch(_client, _owner, _repo, _pr_number, []), do: :ok

  defp maybe_update_branch(client, owner, repo, pr_number, _previous_merges) do
    case Deploy.GitHub.update_branch(client, owner, repo, pr_number) do
      {:ok, _} -> poll_until_mergeable(client, owner, repo, pr_number)
      {:error, reason} -> {:error, reason}
    end
  end

  # update_branch returns 202 (async). Poll the PR until GitHub
  # reports it as mergeable, meaning the branch update is complete.
  defp poll_until_mergeable(client, owner, repo, pr_number, attempts \\ 10) do
    case Deploy.GitHub.get_pr(client, owner, repo, pr_number) do
      {:ok, %{"mergeable" => true}} ->
        :ok

      {:ok, _} when attempts > 0 ->
        Logger.info("PR ##{pr_number} not yet mergeable, waiting...")
        Process.sleep(2_000)
        poll_until_mergeable(client, owner, repo, pr_number, attempts - 1)

      {:ok, _} ->
        {:error, "PR ##{pr_number} still not mergeable after polling"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def compensate(_result, _arguments, _context, _options) do
    Logger.warning("MergePRs compensation called — merges cannot be undone")
    :ok
  end
end
