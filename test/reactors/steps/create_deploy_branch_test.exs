defmodule Deploy.Reactors.Steps.CreateDeployBranchTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  describe "run/3" do
    test "checks out base branch and creates deploy branch" do
      Deploy.Git.Mock
      |> expect(:cmd, fn ["checkout", "staging"], _opts -> {"", 0} end)
      |> expect(:cmd, fn ["checkout", "-b", "deploy-20260201"], _opts -> {"", 0} end)

      args = %{workspace: "/tmp/ws", deploy_date: "20260201", base_branch: "staging"}
      assert {:ok, "deploy-20260201"} = Deploy.Reactors.Steps.CreateDeployBranch.run(args, %{}, [])
    end

    test "returns error when checkout fails" do
      expect(Deploy.Git.Mock, :cmd, fn ["checkout", "staging"], _opts -> {"error", 1} end)

      args = %{workspace: "/tmp/ws", deploy_date: "20260201", base_branch: "staging"}
      assert {:error, msg} = Deploy.Reactors.Steps.CreateDeployBranch.run(args, %{}, [])
      assert msg =~ "Failed to create deploy branch"
    end
  end

  describe "compensate/4" do
    test "switches to staging and deletes branch" do
      Deploy.Git.Mock
      |> expect(:cmd, fn ["checkout", "staging"], _opts -> {"", 0} end)
      |> expect(:cmd, fn ["branch", "-D", "deploy-20260201"], _opts -> {"", 0} end)

      assert :ok =
               Deploy.Reactors.Steps.CreateDeployBranch.compensate(
                 "deploy-20260201",
                 %{workspace: "/tmp/ws"},
                 %{},
                 []
               )
    end
  end
end
