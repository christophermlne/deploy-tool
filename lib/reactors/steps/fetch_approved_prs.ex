defmodule Deploy.Reactors.Steps.FetchApprovedPRs do
  @moduledoc """
  Discovers approved PRs targeting staging, or fetches specific PRs by number.

  If `pr_numbers` is non-empty, fetches those specific PRs.
  Otherwise, lists open PRs targeting staging and filters to approved ones.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(arguments, _context, _options) do
    client = arguments.client
    owner = arguments.owner
    repo = arguments.repo
    pr_numbers = arguments.pr_numbers

    if pr_numbers != [] do
      fetch_specific_prs(client, owner, repo, pr_numbers)
    else
      discover_approved_prs(client, owner, repo)
    end
  end

  defp fetch_specific_prs(client, owner, repo, pr_numbers) do
    pr_numbers
    |> Enum.reduce_while({:ok, []}, fn number, {:ok, acc} ->
      case Deploy.GitHub.get_pr(client, owner, repo, number) do
        {:ok, pr} -> {:cont, {:ok, [normalize_pr(pr) | acc]}}
        {:error, reason} -> {:halt, {:error, "Failed to fetch PR ##{number}: #{inspect(reason)}"}}
      end
    end)
    |> then(fn
      {:ok, prs} -> {:ok, Enum.reverse(prs)}
      error -> error
    end)
  end

  defp discover_approved_prs(client, owner, repo) do
    with {:ok, prs} <- Deploy.GitHub.list_prs(client, owner, repo, base: "staging", state: "open") do
      approved =
        prs
        |> Enum.filter(fn pr ->
          case Deploy.GitHub.pr_approved?(client, owner, repo, pr["number"]) do
            {:ok, true} -> true
            _ -> false
          end
        end)
        |> Enum.map(&normalize_pr/1)

      Logger.info("Found #{length(approved)} approved PRs targeting staging")
      {:ok, approved}
    end
  end

  defp normalize_pr(pr) do
    %{
      number: pr["number"],
      title: pr["title"],
      head_ref: get_in(pr, ["head", "ref"])
    }
  end

end
