defmodule Deploy.Reactors.Steps.UpdatePRDescription do
  @moduledoc """
  Populates the deploy PR body with information about included PRs.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(%{client: client, owner: owner, repo: repo, pr_number: pr_number, merged_prs: merged_prs, deploy_branch: _deploy_branch}, _context, _options) do
    pr_numbers = Enum.map(merged_prs, & &1.number)

    with {:ok, issues} <- Deploy.GitHub.closing_issues_for_prs(client, owner, repo, pr_numbers) do
      body = build_description(merged_prs, issues)
      Deploy.GitHub.update_pr(client, owner, repo, pr_number, %{body: body})
    end
  end

  defp build_description(merged_prs, issues) do
    pr_section = "PRs\n" <> Enum.map_join(merged_prs, "\n", &"##{&1.number}")

    case issues do
      [] -> pr_section
      _ -> "Issues\n" <> Enum.map_join(issues, "\n", &"##{&1}") <> "\n\n" <> pr_section
    end
  end
end
