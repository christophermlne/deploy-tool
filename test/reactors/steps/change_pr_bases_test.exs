defmodule Deploy.Reactors.Steps.ChangePRBasesTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.ChangePRBases

  defp stub_client(plug), do: Req.new(plug: plug)

  test "changes base for each PR and returns them" do
    client = stub_client(fn conn ->
      Req.Test.json(conn, %{"number" => 1, "base" => %{"ref" => "deploy-20260201"}})
    end)

    prs = [
      %{number: 1, title: "PR 1", head_ref: "f1"},
      %{number: 2, title: "PR 2", head_ref: "f2"}
    ]

    arguments = %{
      client: client,
      owner: "o",
      repo: "r",
      prs: prs,
      deploy_branch: "deploy-20260201"
    }

    assert {:ok, changed} = ChangePRBases.run(arguments, %{}, [])
    assert length(changed) == 2
  end

  test "returns error if a change fails" do
    call_count = :counters.new(1, [:atomics])

    client = stub_client(fn conn ->
      :counters.add(call_count, 1, 1)

      case :counters.get(call_count, 1) do
        1 -> Req.Test.json(conn, %{"number" => 1})
        2 -> conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"message" => "nope"})
      end
    end)

    prs = [
      %{number: 1, title: "PR 1", head_ref: "f1"},
      %{number: 2, title: "PR 2", head_ref: "f2"}
    ]

    arguments = %{
      client: client,
      owner: "o",
      repo: "r",
      prs: prs,
      deploy_branch: "deploy-20260201"
    }

    assert {:error, msg} = ChangePRBases.run(arguments, %{}, [])
    assert msg =~ "PR #2"
  end

  test "compensation reverts PRs back to staging" do
    reverted = :counters.new(1, [:atomics])

    client = stub_client(fn conn ->
      {:ok, body, _} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["base"] == "staging"
      :counters.add(reverted, 1, 1)
      Req.Test.json(conn, %{"number" => 1})
    end)

    changed_prs = [
      %{number: 1, title: "PR 1", head_ref: "f1"},
      %{number: 2, title: "PR 2", head_ref: "f2"}
    ]

    arguments = %{client: client, owner: "o", repo: "r"}

    assert :ok = ChangePRBases.compensate(changed_prs, arguments, %{}, [])
    assert :counters.get(reverted, 1) == 2
  end
end
