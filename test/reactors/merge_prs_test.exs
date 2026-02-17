defmodule Deploy.Reactors.MergePRsTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  defp stub_client(plug), do: Req.new(plug: plug)

  test "full reactor: fetches, validates, retargets, merges, and pulls" do
    call_count = :counters.new(1, [:atomics])

    client = stub_client(fn conn ->
      :counters.add(call_count, 1, 1)
      count = :counters.get(call_count, 1)

      case {conn.method, count} do
        # fetch_approved_prs: GET /repos/o/r/pulls/1
        {"GET", 1} ->
          Req.Test.json(conn, %{
            "number" => 1,
            "title" => "Feature",
            "head" => %{"ref" => "feature-1"}
          })

        # validate_prs: GET /repos/o/r/pulls/1/reviews (approval check)
        {"GET", 2} ->
          Req.Test.json(conn, [
            %{"user" => %{"login" => "reviewer"}, "state" => "APPROVED", "submitted_at" => "2026-01-01T00:00:00Z"}
          ])

        # validate_prs: GET /repos/o/r/commits/feature-1/check-runs (CI check)
        {"GET", 3} ->
          Req.Test.json(conn, %{"check_runs" => [
            %{"name" => "test", "status" => "completed", "conclusion" => "success"}
          ]})

        # change_pr_bases: PATCH /repos/o/r/pulls/1
        {"PATCH", 4} ->
          Req.Test.json(conn, %{"number" => 1, "base" => %{"ref" => "deploy-20260201"}})

        # merge_prs: check_mergeable GET /repos/o/r/pulls/1
        {"GET", 5} ->
          Req.Test.json(conn, %{"mergeable" => true})

        # merge_prs: PUT /repos/o/r/pulls/1/merge
        {"PUT", 6} ->
          Req.Test.json(conn, %{"merged" => true, "sha" => "deadbeef"})
      end
    end)

    # git pull for update_local_branch
    Deploy.Git.Mock
    |> expect(:cmd, fn ["pull", "origin", "deploy-20260201"], _opts ->
      {"Already up to date.", 0}
    end)

    inputs = %{
      deploy_branch: "deploy-20260201",
      workspace: "/tmp/test-workspace",
      client: client,
      owner: "o",
      repo: "r",
      pr_numbers: [1],
      skip_reviews: false,
      skip_ci: false,
      skip_conflicts: false,
      skip_validation: false
    }

    assert {:ok, [merged]} = Reactor.run(Deploy.Reactors.MergePRs, inputs)
    assert merged.number == 1
    assert merged.title == "Feature"
    assert merged.sha == "deadbeef"
  end
end
