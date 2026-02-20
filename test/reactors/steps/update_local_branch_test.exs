defmodule Deploy.Reactors.Steps.UpdateLocalBranchTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  test "pulls from origin" do
    Deploy.Git.Mock
    |> expect(:cmd, fn ["pull", "origin", "deploy-20260201"], opts ->
      assert opts[:cd] == "/tmp/workspace"
      {"Already up to date.", 0}
    end)

    arguments = %{workspace: "/tmp/workspace", deploy_branch: "deploy-20260201"}

    assert {:ok, "/tmp/workspace"} =
             Deploy.Reactors.Steps.UpdateLocalBranch.run(arguments, %{}, [])
  end

  test "returns error on pull failure" do
    Deploy.Git.Mock
    |> expect(:cmd, fn ["pull" | _], _opts ->
      {"fatal: error", 1}
    end)

    arguments = %{workspace: "/tmp/workspace", deploy_branch: "deploy-20260201"}

    assert {:error, msg} =
             Deploy.Reactors.Steps.UpdateLocalBranch.run(arguments, %{}, [])

    assert msg =~ "git pull failed"
  end
end
