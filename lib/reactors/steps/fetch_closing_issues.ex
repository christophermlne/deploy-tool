defmodule Deploy.Reactors.Steps.FetchClosingIssues do
  @moduledoc """
  Fetches closing issue references for merged PRs via GraphQL.

  If the GraphQL query fails (e.g. token lacks permission for
  closingIssuesReferences), compensation returns an empty list
  so the reactor can continue with a PR-only description.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(%{client: client, owner: owner, repo: repo, merged_prs: merged_prs}, _context, _options) do
    pr_numbers = Enum.map(merged_prs, & &1.number)
    Deploy.GitHub.closing_issues_for_prs(client, owner, repo, pr_numbers)
  end

  @impl true
  def compensate(reason, _arguments, _context, _options) do
    Logger.warning("Failed to fetch closing issues, falling back to empty: #{inspect(reason)}")
    {:continue, []}
  end
end
