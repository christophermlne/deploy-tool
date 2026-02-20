defmodule Deploy.Reactors.Steps.UpdatePRDescription do
  @moduledoc """
  Populates the deploy PR body with information about included PRs.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(%{client: client, owner: owner, repo: repo, pr_number: pr_number, merged_prs: merged_prs, deploy_branch: deploy_branch}, _context, _options) do

    body = build_description(deploy_branch, merged_prs)

    Deploy.GitHub.update_pr(client, owner, repo, pr_number, %{body: body})
  end

  defp build_description(_deploy_branch, merged_prs) do
    merged_prs
    |> Enum.map(&"##{&1.number}")
    |> Enum.join("\n")
  end
end
