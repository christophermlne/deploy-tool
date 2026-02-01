defmodule Deploy.Reactors.Steps.CreateWorkspaceTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.CreateWorkspace

  describe "run/3" do
    test "creates a temp directory" do
      assert {:ok, workspace} = CreateWorkspace.run(%{}, %{}, [])
      assert File.dir?(workspace)
      assert String.contains?(workspace, "deploy-")
      File.rm_rf!(workspace)
    end
  end

  describe "compensate/4" do
    test "removes the workspace directory" do
      {:ok, workspace} = CreateWorkspace.run(%{}, %{}, [])
      assert File.dir?(workspace)

      assert :ok = CreateWorkspace.compensate(workspace, %{}, %{}, [])
      refute File.dir?(workspace)
    end

    test "returns ok even if directory doesn't exist" do
      assert :ok = CreateWorkspace.compensate("/tmp/nonexistent-deploy-test", %{}, %{}, [])
    end
  end
end
