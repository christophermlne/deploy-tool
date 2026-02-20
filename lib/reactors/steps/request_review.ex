defmodule Deploy.Reactors.Steps.RequestReview do
  @moduledoc """
  Requests review on the deploy PR. Skips if no reviewers provided.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(%{reviewers: []}, _context, _options), do: {:ok, :skipped}

  def run(%{client: client, owner: owner, repo: repo, pr_number: pr_number, reviewers: reviewers}, _context, _options) do
    Deploy.GitHub.request_review(client, owner, repo, pr_number, reviewers)
  end

end
