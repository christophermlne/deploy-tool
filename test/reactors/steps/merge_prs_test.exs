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
        # First PR merges directly (no update needed)
        {"PUT", 1} ->
          Req.Test.json(conn, %{"merged" => true, "sha" => "aaa"})

        # Second PR: update-branch
        {"PUT", 2} ->
          conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{"message" => "Updating"})

        # Second PR: poll mergeable
        {"GET", 3} ->
          Req.Test.json(conn, %{"mergeable" => true})

        # Second PR: merge
        {"PUT", 4} ->
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
    client = stub_client(fn conn ->
      conn |> Plug.Conn.put_status(405) |> Req.Test.json(%{"message" => "not mergeable"})
    end)

    prs = [%{number: 1, title: "PR 1", head_ref: "f1"}]
    arguments = %{client: client, owner: "o", repo: "r", prs: prs}

    assert {:error, msg} = MergePRs.run(arguments, %{}, [])
    assert msg =~ "PR #1"
  end

  test "compensation returns ok with warning" do
    assert :ok = MergePRs.compensate([], %{}, %{}, [])
  end
end
