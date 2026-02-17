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

  @impl true
  def compensate(_result, _arguments, _context, _options), do: :ok

  defp build_description(deploy_branch, merged_prs) do
    title = format_heading(deploy_branch)
    pr_lines = Enum.map_join(merged_prs, "\n", fn pr ->
      "- ##{pr.number} #{pr.title}"
    end)

    """
    ## #{title}

    ### Included Pull Requests
    #{pr_lines}

    ### Checklist
    - [ ] Verify deployment completes successfully
    - [ ] Smoke test critical paths
    - [ ] Check error rates in monitoring
    """
    |> String.trim()
  end

  defp format_heading("deploy-" <> date) do
    <<y::binary-size(4), m::binary-size(2), d::binary-size(2)>> = date
    "Deploy #{y}-#{m}-#{d}"
  end

  defp format_heading(branch), do: "Deploy #{branch}"
end
