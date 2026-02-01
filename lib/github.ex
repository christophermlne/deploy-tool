defmodule Deploy.GitHub do
  @moduledoc """
  GitHub API client for deployment operations.

  Uses the GitHub REST API for most operations. Consider GraphQL
  for complex queries that need related data in a single call.
  """

  require Logger

  @base_url "https://api.github.com"

  @doc """
  Creates a configured Req client for GitHub API calls.
  """
  def client(token) do
    Req.new(
      base_url: @base_url,
      headers: [
        {"authorization", "Bearer #{token}"},
        {"accept", "application/vnd.github+json"},
        {"x-github-api-version", "2022-11-28"}
      ]
    )
  end

  @doc """
  Changes the base branch of a pull request.

  This is used to retarget approved PRs from staging to the deploy branch.
  """
  def change_pr_base(client, owner, repo, pr_number, new_base) do
    Logger.info("Changing PR ##{pr_number} base to #{new_base}")

    case Req.patch(client,
           url: "/repos/#{owner}/#{repo}/pulls/#{pr_number}",
           json: %{base: new_base}
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to change PR base (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Updates a pull request branch with the latest from its base branch.

  This is needed before merging when the base branch has changed
  (e.g., a previous PR was just merged into it).
  """
  def update_branch(client, owner, repo, pr_number) do
    Logger.info("Updating branch for PR ##{pr_number}")

    case Req.put(client,
           url: "/repos/#{owner}/#{repo}/pulls/#{pr_number}/update-branch",
           json: %{}
         ) do
      {:ok, %{status: 202, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to update branch (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Merges a pull request.
  """
  def merge_pr(client, owner, repo, pr_number, opts \\ []) do
    merge_method = Keyword.get(opts, :merge_method, "squash")
    commit_title = Keyword.get(opts, :commit_title)

    Logger.info("Merging PR ##{pr_number} via #{merge_method}")

    body =
      %{merge_method: merge_method}
      |> maybe_add(:commit_title, commit_title)

    case Req.put(client,
           url: "/repos/#{owner}/#{repo}/pulls/#{pr_number}/merge",
           json: body
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to merge PR (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Creates a pull request.
  """
  def create_pr(client, owner, repo, attrs) do
    Logger.info("Creating PR: #{attrs.title}")

    case Req.post(client,
           url: "/repos/#{owner}/#{repo}/pulls",
           json: attrs
         ) do
      {:ok, %{status: 201, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to create PR (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Updates a pull request's title or body.
  """
  def update_pr(client, owner, repo, pr_number, attrs) do
    Logger.info("Updating PR ##{pr_number}")

    case Req.patch(client,
           url: "/repos/#{owner}/#{repo}/pulls/#{pr_number}",
           json: attrs
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to update PR (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets the status of CI checks for a ref (branch or SHA).
  """
  def get_check_runs(client, owner, repo, ref) do
    case Req.get(client, url: "/repos/#{owner}/#{repo}/commits/#{ref}/check-runs") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to get check runs (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Checks if all CI checks have passed for a ref.

  Returns :pending if any checks are still running.
  """
  def ci_status(client, owner, repo, ref) do
    with {:ok, %{"check_runs" => runs}} <- get_check_runs(client, owner, repo, ref) do
      cond do
        Enum.empty?(runs) ->
          {:ok, :pending}

        Enum.any?(runs, &(&1["status"] != "completed")) ->
          {:ok, :pending}

        Enum.all?(runs, &(&1["conclusion"] == "success")) ->
          {:ok, :success}

        true ->
          failed = Enum.filter(runs, &(&1["conclusion"] != "success"))
          {:ok, {:failed, failed}}
      end
    end
  end

  @doc """
  Requests a review from a user.
  """
  def request_review(client, owner, repo, pr_number, reviewers) do
    Logger.info("Requesting review on PR ##{pr_number} from #{inspect(reviewers)}")

    case Req.post(client,
           url: "/repos/#{owner}/#{repo}/pulls/#{pr_number}/requested_reviewers",
           json: %{reviewers: List.wrap(reviewers)}
         ) do
      {:ok, %{status: 201, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to request review (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets the reviews for a pull request.
  """
  def get_reviews(client, owner, repo, pr_number) do
    case Req.get(client, url: "/repos/#{owner}/#{repo}/pulls/#{pr_number}/reviews") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to get reviews (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Checks if a PR has been approved.
  """
  def pr_approved?(client, owner, repo, pr_number) do
    with {:ok, reviews} <- get_reviews(client, owner, repo, pr_number) do
      # Get the latest review state per user
      latest_states =
        reviews
        |> Enum.group_by(& &1["user"]["login"])
        |> Enum.map(fn {_user, user_reviews} ->
          user_reviews
          |> Enum.max_by(& &1["submitted_at"])
          |> Map.get("state")
        end)

      approved = Enum.any?(latest_states, &(&1 == "APPROVED"))
      changes_requested = Enum.any?(latest_states, &(&1 == "CHANGES_REQUESTED"))

      {:ok, approved && !changes_requested}
    end
  end

  @doc """
  Updates a release's body/description.
  """
  def update_release(client, owner, repo, release_id, body) do
    Logger.info("Updating release #{release_id}")

    case Req.patch(client,
           url: "/repos/#{owner}/#{repo}/releases/#{release_id}",
           json: %{body: body}
         ) do
      {:ok, %{status: 200, body: resp}} ->
        {:ok, resp}

      {:ok, %{status: status, body: resp}} ->
        {:error, "Failed to update release (#{status}): #{inspect(resp)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Lists pull requests for a repository.

  Options:
    - `base` — filter by base branch
    - `state` — PR state, default "open"
  """
  def list_prs(client, owner, repo, opts \\ []) do
    base = Keyword.get(opts, :base)
    state = Keyword.get(opts, :state, "open")

    params =
      %{state: state}
      |> maybe_add(:base, base)

    case Req.get(client, url: "/repos/#{owner}/#{repo}/pulls", params: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to list PRs (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets a single pull request by number.
  """
  def get_pr(client, owner, repo, pr_number) do
    case Req.get(client, url: "/repos/#{owner}/#{repo}/pulls/#{pr_number}") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to get PR (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets a release by tag name.
  """
  def get_release_by_tag(client, owner, repo, tag) do
    case Req.get(client, url: "/repos/#{owner}/#{repo}/releases/tags/#{tag}") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to get release (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  # Helper to conditionally add keys to a map
  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
