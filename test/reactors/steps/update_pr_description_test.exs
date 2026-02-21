defmodule Deploy.Reactors.Steps.UpdatePRDescriptionTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.UpdatePRDescription

  defp stub_client(expected_body) do
    Req.new(plug: fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      case {conn.method, conn.request_path} do
        {"POST", "/graphql"} ->
          # Return empty closing issues for all PRs
          Req.Test.json(conn, %{"data" => %{"repository" => %{}}})

        {"PATCH", "/repos/o/r/pulls/99"} ->
          assert decoded["body"] == expected_body
          Req.Test.json(conn, %{"number" => 99})
      end
    end)
  end

  test "builds description with PR numbers only" do
    client = stub_client("PRs\n#1\n#2")

    arguments = %{
      client: client,
      owner: "o",
      repo: "r",
      pr_number: 99,
      deploy_branch: "deploy-20260201",
      merged_prs: [
        %{number: 1, title: "Feature A", sha: "aaa"},
        %{number: 2, title: "Feature B", sha: "bbb"}
      ]
    }

    assert {:ok, _} = UpdatePRDescription.run(arguments, %{}, [])
  end

  test "handles empty merged_prs list" do
    client = stub_client("")

    arguments = %{
      client: client,
      owner: "o",
      repo: "r",
      pr_number: 99,
      deploy_branch: "deploy-20260201",
      merged_prs: []
    }

    assert {:ok, _} = UpdatePRDescription.run(arguments, %{}, [])
  end

  test "handles single merged PR" do
    client = stub_client("PRs\n#42")

    arguments = %{
      client: client,
      owner: "o",
      repo: "r",
      pr_number: 99,
      deploy_branch: "deploy-20260201",
      merged_prs: [%{number: 42, title: "Solo PR", sha: "xyz"}]
    }

    assert {:ok, _} = UpdatePRDescription.run(arguments, %{}, [])
  end
end
