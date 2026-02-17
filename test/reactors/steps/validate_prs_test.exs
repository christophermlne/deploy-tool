defmodule Deploy.Reactors.Steps.ValidatePRsTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.ValidatePRs

  defp stub_client(plug), do: Req.new(plug: plug)

  defp make_prs(numbers) do
    Enum.map(numbers, fn n ->
      %{number: n, title: "PR #{n}", head_ref: "feature-#{n}"}
    end)
  end

  describe "all PRs pass validation" do
    test "returns unchanged PR list when all checks pass" do
      call_count = :counters.new(1, [:atomics])

      client = stub_client(fn conn ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        case count do
          # PR #1 reviews (approved)
          1 ->
            Req.Test.json(conn, [
              %{"user" => %{"login" => "reviewer"}, "state" => "APPROVED", "submitted_at" => "2026-01-01T00:00:00Z"}
            ])

          # PR #1 CI status (success)
          2 ->
            Req.Test.json(conn, %{"check_runs" => [
              %{"name" => "test", "status" => "completed", "conclusion" => "success"}
            ]})

          # PR #2 reviews (approved)
          3 ->
            Req.Test.json(conn, [
              %{"user" => %{"login" => "reviewer"}, "state" => "APPROVED", "submitted_at" => "2026-01-01T00:00:00Z"}
            ])

          # PR #2 CI status (success)
          4 ->
            Req.Test.json(conn, %{"check_runs" => [
              %{"name" => "test", "status" => "completed", "conclusion" => "success"}
            ]})
        end
      end)

      prs = make_prs([1, 2])
      arguments = %{client: client, owner: "o", repo: "r", prs: prs}

      assert {:ok, ^prs} = ValidatePRs.run(arguments, %{}, [])
    end
  end

  describe "approval check" do
    test "returns error when PR has no approval" do
      client = stub_client(fn conn ->
        case conn.request_path do
          # Reviews endpoint - no approvals
          "/repos/o/r/pulls/1/reviews" ->
            Req.Test.json(conn, [])

          # CI - success (but won't matter, we fail on approval)
          "/repos/o/r/commits/feature-1/check-runs" ->
            Req.Test.json(conn, %{"check_runs" => [
              %{"name" => "test", "status" => "completed", "conclusion" => "success"}
            ]})
        end
      end)

      prs = make_prs([1])
      arguments = %{client: client, owner: "o", repo: "r", prs: prs}

      assert {:error, %{validation_failures: failures}} = ValidatePRs.run(arguments, %{}, [])
      assert length(failures) == 1
      assert hd(failures).number == 1
      assert :no_approval in hd(failures).reasons
    end

    test "returns error when PR has CHANGES_REQUESTED" do
      client = stub_client(fn conn ->
        case conn.request_path do
          # Reviews with changes requested
          "/repos/o/r/pulls/1/reviews" ->
            Req.Test.json(conn, [
              %{"user" => %{"login" => "reviewer"}, "state" => "CHANGES_REQUESTED", "submitted_at" => "2026-01-01T00:00:00Z"}
            ])

          # CI - success
          "/repos/o/r/commits/feature-1/check-runs" ->
            Req.Test.json(conn, %{"check_runs" => [
              %{"name" => "test", "status" => "completed", "conclusion" => "success"}
            ]})
        end
      end)

      prs = make_prs([1])
      arguments = %{client: client, owner: "o", repo: "r", prs: prs}

      assert {:error, %{validation_failures: failures}} = ValidatePRs.run(arguments, %{}, [])
      assert :no_approval in hd(failures).reasons
    end
  end

  describe "CI check" do
    test "returns ci_pending when checks are still running" do
      client = stub_client(fn conn ->
        case conn.request_path do
          # Reviews - approved
          "/repos/o/r/pulls/1/reviews" ->
            Req.Test.json(conn, [
              %{"user" => %{"login" => "reviewer"}, "state" => "APPROVED", "submitted_at" => "2026-01-01T00:00:00Z"}
            ])

          # CI - pending
          "/repos/o/r/commits/feature-1/check-runs" ->
            Req.Test.json(conn, %{"check_runs" => [
              %{"name" => "test", "status" => "in_progress", "conclusion" => nil}
            ]})
        end
      end)

      prs = make_prs([1])
      arguments = %{client: client, owner: "o", repo: "r", prs: prs}

      assert {:error, %{validation_failures: failures}} = ValidatePRs.run(arguments, %{}, [])
      assert :ci_pending in hd(failures).reasons
    end

    test "returns ci_failed with check names when checks fail" do
      client = stub_client(fn conn ->
        case conn.request_path do
          # Reviews - approved
          "/repos/o/r/pulls/1/reviews" ->
            Req.Test.json(conn, [
              %{"user" => %{"login" => "reviewer"}, "state" => "APPROVED", "submitted_at" => "2026-01-01T00:00:00Z"}
            ])

          # CI - failed
          "/repos/o/r/commits/feature-1/check-runs" ->
            Req.Test.json(conn, %{"check_runs" => [
              %{"name" => "lint", "status" => "completed", "conclusion" => "failure"},
              %{"name" => "test", "status" => "completed", "conclusion" => "success"}
            ]})
        end
      end)

      prs = make_prs([1])
      arguments = %{client: client, owner: "o", repo: "r", prs: prs}

      assert {:error, %{validation_failures: failures}} = ValidatePRs.run(arguments, %{}, [])
      assert {:ci_failed, ["lint"]} in hd(failures).reasons
    end
  end

  describe "multiple PRs with different failures" do
    test "aggregates all failures" do
      call_count = :counters.new(1, [:atomics])

      client = stub_client(fn conn ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        case count do
          # PR #1 reviews (no approval)
          1 -> Req.Test.json(conn, [])

          # PR #1 CI (success - but PR fails on approval)
          2 ->
            Req.Test.json(conn, %{"check_runs" => [
              %{"name" => "test", "status" => "completed", "conclusion" => "success"}
            ]})

          # PR #2 reviews (approved)
          3 ->
            Req.Test.json(conn, [
              %{"user" => %{"login" => "reviewer"}, "state" => "APPROVED", "submitted_at" => "2026-01-01T00:00:00Z"}
            ])

          # PR #2 CI (pending)
          4 ->
            Req.Test.json(conn, %{"check_runs" => [
              %{"name" => "test", "status" => "in_progress", "conclusion" => nil}
            ]})
        end
      end)

      prs = make_prs([1, 2])
      arguments = %{client: client, owner: "o", repo: "r", prs: prs}

      assert {:error, %{validation_failures: failures}} = ValidatePRs.run(arguments, %{}, [])
      assert length(failures) == 2

      pr1_failure = Enum.find(failures, &(&1.number == 1))
      pr2_failure = Enum.find(failures, &(&1.number == 2))

      assert :no_approval in pr1_failure.reasons
      assert :ci_pending in pr2_failure.reasons
    end
  end

  describe "skip options" do
    test "skip_reviews bypasses approval check" do
      client = stub_client(fn conn ->
        case conn.request_path do
          # CI - success (reviews won't be checked)
          "/repos/o/r/commits/feature-1/check-runs" ->
            Req.Test.json(conn, %{"check_runs" => [
              %{"name" => "test", "status" => "completed", "conclusion" => "success"}
            ]})
        end
      end)

      prs = make_prs([1])
      arguments = %{client: client, owner: "o", repo: "r", prs: prs, skip_reviews: true}

      assert {:ok, ^prs} = ValidatePRs.run(arguments, %{}, [])
    end

    test "skip_ci bypasses CI check" do
      client = stub_client(fn conn ->
        case conn.request_path do
          # Reviews - approved (CI won't be checked)
          "/repos/o/r/pulls/1/reviews" ->
            Req.Test.json(conn, [
              %{"user" => %{"login" => "reviewer"}, "state" => "APPROVED", "submitted_at" => "2026-01-01T00:00:00Z"}
            ])
        end
      end)

      prs = make_prs([1])
      arguments = %{client: client, owner: "o", repo: "r", prs: prs, skip_ci: true}

      assert {:ok, ^prs} = ValidatePRs.run(arguments, %{}, [])
    end

    test "skip_validation bypasses all checks" do
      # No HTTP calls should be made
      client = stub_client(fn conn ->
        flunk("No HTTP calls expected, got: #{conn.request_path}")
      end)

      prs = make_prs([1])
      arguments = %{client: client, owner: "o", repo: "r", prs: prs, skip_validation: true}

      assert {:ok, ^prs} = ValidatePRs.run(arguments, %{}, [])
    end
  end

  describe "compensation" do
    test "compensate is a no-op" do
      assert :ok = ValidatePRs.compensate(nil, %{}, %{}, [])
    end
  end
end
