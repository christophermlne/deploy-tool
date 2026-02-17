defmodule Deploy.Reactors.Steps.UpdatePRDescriptionTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.UpdatePRDescription

  defp stub_client(plug), do: Req.new(plug: plug)

  test "builds and sets markdown description" do
    client = stub_client(fn conn ->
      {:ok, body, _} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert decoded["body"] =~ "## Deploy 2026-02-01"
      assert decoded["body"] =~ "- #1 Feature A"
      assert decoded["body"] =~ "- #2 Feature B"
      assert decoded["body"] =~ "### Checklist"
      assert decoded["body"] =~ "Smoke test"

      Req.Test.json(conn, %{"number" => 99})
    end)

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
    client = stub_client(fn conn ->
      {:ok, body, _} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["body"] =~ "### Included Pull Requests"
      Req.Test.json(conn, %{"number" => 99})
    end)

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
end
