defmodule Deploy.Reactors.Steps.FetchApprovedPRsTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.FetchApprovedPRs

  defp stub_client(plug), do: Req.new(plug: plug)

  describe "with explicit pr_numbers" do
    test "fetches specific PRs by number" do
      client = stub_client(fn conn ->
        # GET /repos/o/r/pulls/:number
        number = conn.path_info |> List.last() |> String.to_integer()

        Req.Test.json(conn, %{
          "number" => number,
          "title" => "PR #{number}",
          "head" => %{"ref" => "feature-#{number}"}
        })
      end)

      arguments = %{client: client, owner: "o", repo: "r", pr_numbers: [1, 2]}

      assert {:ok, prs} = FetchApprovedPRs.run(arguments, %{}, [])
      assert length(prs) == 2
      assert Enum.at(prs, 0).number == 1
      assert Enum.at(prs, 1).number == 2
      assert Enum.at(prs, 0).head_ref == "feature-1"
    end

    test "returns error if a PR fetch fails" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "not found"})
      end)

      arguments = %{client: client, owner: "o", repo: "r", pr_numbers: [99]}

      assert {:error, msg} = FetchApprovedPRs.run(arguments, %{}, [])
      assert msg =~ "Failed to fetch PR #99"
    end
  end

  describe "auto-discovery" do
    test "lists and filters to approved PRs" do
      call_count = :counters.new(1, [:atomics])

      client = stub_client(fn conn ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        case {conn.method, count} do
          # First call: list PRs
          {"GET", 1} ->
            Req.Test.json(conn, [
              %{"number" => 1, "title" => "Approved PR", "head" => %{"ref" => "f1"}},
              %{"number" => 2, "title" => "Not approved", "head" => %{"ref" => "f2"}}
            ])

          # Second call: reviews for PR #1 — approved
          {"GET", 2} ->
            Req.Test.json(conn, [
              %{"user" => %{"login" => "reviewer"}, "state" => "APPROVED", "submitted_at" => "2026-01-01T00:00:00Z"}
            ])

          # Third call: reviews for PR #2 — changes requested
          {"GET", 3} ->
            Req.Test.json(conn, [
              %{"user" => %{"login" => "reviewer"}, "state" => "CHANGES_REQUESTED", "submitted_at" => "2026-01-01T00:00:00Z"}
            ])
        end
      end)

      arguments = %{client: client, owner: "o", repo: "r", pr_numbers: []}

      assert {:ok, [pr]} = FetchApprovedPRs.run(arguments, %{}, [])
      assert pr.number == 1
      assert pr.title == "Approved PR"
    end
  end
end
