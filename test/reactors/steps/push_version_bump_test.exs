defmodule Deploy.Reactors.Steps.PushVersionBumpTest do
  use ExUnit.Case, async: false

  import Mox

  alias Deploy.Reactors.Steps.PushVersionBump

  setup :verify_on_exit!

  describe "run/3" do
    test "pushes branch to origin" do
      expect(Deploy.Git.Mock, :cmd, fn ["push", "origin", "deploy-20260201"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)

      args = %{workspace: "/tmp/ws", deploy_branch: "deploy-20260201"}
      assert {:ok, "deploy-20260201"} = PushVersionBump.run(args, %{}, [])
    end

    test "returns error on push failure" do
      expect(Deploy.Git.Mock, :cmd, fn ["push" | _], _opts -> {"rejected", 1} end)

      args = %{workspace: "/tmp/ws", deploy_branch: "deploy-20260201"}
      assert {:error, msg} = PushVersionBump.run(args, %{}, [])
      assert msg =~ "Git push failed"
    end
  end

  describe "compensate/4" do
    test "force pushes to remove version bump commit" do
      expect(Deploy.Git.Mock, :cmd, fn ["push", "--force-with-lease", "origin", "deploy-20260201"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)

      args = %{workspace: "/tmp/ws", deploy_branch: "deploy-20260201"}
      assert :ok = PushVersionBump.compensate("deploy-20260201", args, %{}, [])
    end

    test "returns ok even when force push fails" do
      expect(Deploy.Git.Mock, :cmd, fn ["push", "--force-with-lease" | _], _opts ->
        {"error", 1}
      end)

      args = %{workspace: "/tmp/ws", deploy_branch: "deploy-20260201"}
      assert :ok = PushVersionBump.compensate("deploy-20260201", args, %{}, [])
    end
  end
end
