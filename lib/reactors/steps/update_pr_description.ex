defmodule Deploy.Reactors.Steps.UpdatePRDescription do
  @moduledoc """
  Populates the deploy PR body with information about included PRs.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(arguments, _context, _options) do
    client = arguments.client
    owner = arguments.owner
    repo = arguments.repo
    pr_number = arguments.pr_number
    merged_prs = arguments.merged_prs
    deploy_branch = arguments.deploy_branch

    body = build_description(deploy_branch, merged_prs)

    Deploy.GitHub.update_pr(client, owner, repo, pr_number, %{body: body})
  end

  defp build_description(_deploy_branch, merged_prs) do
    merged_prs
    |> Enum.map(&"##{&1.number}")
    |> Enum.join("\n")
  end
end
