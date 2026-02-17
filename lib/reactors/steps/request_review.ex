defmodule Deploy.Reactors.Steps.RequestReview do
  @moduledoc """
  Requests review on the deploy PR. Skips if no reviewers provided.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(arguments, _context, _options) do
    reviewers = arguments.reviewers

    if reviewers == [] do
      {:ok, :skipped}
    else
      client = arguments.client
      owner = arguments.owner
      repo = arguments.repo
      pr_number = arguments.pr_number

      Deploy.GitHub.request_review(client, owner, repo, pr_number, reviewers)
    end
  end

  @impl true
  def compensate(_result, _arguments, _context, _options), do: :ok
end
