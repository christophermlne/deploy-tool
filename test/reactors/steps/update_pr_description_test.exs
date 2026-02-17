defmodule Deploy.Reactors.Steps.UpdatePRDescriptionTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.UpdatePRDescription

  defp stub_client(plug), do: Req.new(plug: plug)

  test "builds description with PR numbers only" do
    client = stub_client(fn conn ->
      {:ok, body, _} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      # Should just be PR numbers, one per line
      assert decoded["body"] == "#1\n#2"

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
      assert decoded["body"] == ""
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

  test "handles single merged PR" do
    client = stub_client(fn conn ->
      {:ok, body, _} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["body"] == "#42"
      Req.Test.json(conn, %{"number" => 99})
    end)

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
