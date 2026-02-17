defmodule Deploy.Reactors.Steps.MergePRsTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.MergePRs

  defp stub_client(plug), do: Req.new(plug: plug)

  test "merges each PR, updating branch between merges" do
    call_count = :counters.new(1, [:atomics])

    client = stub_client(fn conn ->
      :counters.add(call_count, 1, 1)
      count = :counters.get(call_count, 1)

      case {conn.method, count} do
        # First PR: check mergeable
        {"GET", 1} ->
          Req.Test.json(conn, %{"mergeable" => true})

        # First PR: merge
        {"PUT", 2} ->
          Req.Test.json(conn, %{"merged" => true, "sha" => "aaa"})

        # Second PR: update-branch
        {"PUT", 3} ->
          conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{"message" => "Updating"})

        # Second PR: poll mergeable (after update_branch)
        {"GET", 4} ->
          Req.Test.json(conn, %{"mergeable" => true})

        # Second PR: check mergeable (before merge)
        {"GET", 5} ->
          Req.Test.json(conn, %{"mergeable" => true})

        # Second PR: merge
        {"PUT", 6} ->
          Req.Test.json(conn, %{"merged" => true, "sha" => "bbb"})
      end
    end)

    prs = [
      %{number: 1, title: "PR 1", head_ref: "f1"},
      %{number: 2, title: "PR 2", head_ref: "f2"}
    ]

    arguments = %{client: client, owner: "o", repo: "r", prs: prs}

    assert {:ok, merged} = MergePRs.run(arguments, %{}, [])
    assert length(merged) == 2
    assert Enum.at(merged, 0).sha == "aaa"
    assert Enum.at(merged, 1).sha == "bbb"
  end

  test "returns error on merge failure" do
    call_count = :counters.new(1, [:atomics])

    client = stub_client(fn conn ->
      :counters.add(call_count, 1, 1)
      count = :counters.get(call_count, 1)

      case count do
        # Check mergeable - OK
        1 -> Req.Test.json(conn, %{"mergeable" => true})
        # Merge fails
        2 -> conn |> Plug.Conn.put_status(405) |> Req.Test.json(%{"message" => "not mergeable"})
      end
    end)

    prs = [%{number: 1, title: "PR 1", head_ref: "f1"}]
    arguments = %{client: client, owner: "o", repo: "r", prs: prs}

    assert {:error, msg} = MergePRs.run(arguments, %{}, [])
    assert msg =~ "PR #1"
  end

  describe "conflict checking" do
    test "returns merge_conflict error when PR has conflicts" do
      client = stub_client(fn conn ->
        # Check mergeable - false (conflict)
        Req.Test.json(conn, %{"mergeable" => false})
      end)

      prs = [%{number: 1, title: "PR 1", head_ref: "f1"}]
      arguments = %{client: client, owner: "o", repo: "r", prs: prs}

      assert {:error, msg} = MergePRs.run(arguments, %{}, [])
      assert msg =~ "merge_conflict"
      assert msg =~ "1"
    end

    test "skip_conflicts bypasses conflict check" do
      call_count = :counters.new(1, [:atomics])

      client = stub_client(fn conn ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        case count do
          # No get_pr call for check_mergeable (skipped)
          # Direct merge
          1 -> Req.Test.json(conn, %{"merged" => true, "sha" => "aaa"})
        end
      end)

      prs = [%{number: 1, title: "PR 1", head_ref: "f1"}]
      arguments = %{client: client, owner: "o", repo: "r", prs: prs, skip_conflicts: true}

      assert {:ok, merged} = MergePRs.run(arguments, %{}, [])
      assert length(merged) == 1
    end

    test "polls for mergeable when nil" do
      call_count = :counters.new(1, [:atomics])

      client = stub_client(fn conn ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        case count do
          # First poll - nil (GitHub still computing)
          1 -> Req.Test.json(conn, %{"mergeable" => nil})
          # Second poll - true
          2 -> Req.Test.json(conn, %{"mergeable" => true})
          # Merge
          3 -> Req.Test.json(conn, %{"merged" => true, "sha" => "aaa"})
        end
      end)

      prs = [%{number: 1, title: "PR 1", head_ref: "f1"}]
      arguments = %{client: client, owner: "o", repo: "r", prs: prs}

      assert {:ok, merged} = MergePRs.run(arguments, %{}, [])
      assert length(merged) == 1
    end

    test "assumes conflict after too many nil polls" do
      client = stub_client(fn conn ->
        # Always returns nil
        Req.Test.json(conn, %{"mergeable" => nil})
      end)

      prs = [%{number: 1, title: "PR 1", head_ref: "f1"}]
      arguments = %{client: client, owner: "o", repo: "r", prs: prs}

      # This test takes ~5 seconds due to polling
      assert {:error, msg} = MergePRs.run(arguments, %{}, [])
      assert msg =~ "merge_conflict"
    end
  end

  test "compensation returns ok with warning" do
    assert :ok = MergePRs.compensate([], %{}, %{}, [])
  end
end
