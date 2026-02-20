defmodule Deploy.Reactors.Steps.GitPushTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  describe "run/3" do
    test "pushes branch on success" do
      expect(Deploy.Git.Mock, :cmd, fn ["push", "-u", "origin", "deploy-20260201"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)

      args = %{workspace: "/tmp/ws", branch: "deploy-20260201"}
      assert {:ok, "deploy-20260201"} = Deploy.Reactors.Steps.GitPush.run(args, %{}, [])
    end

    test "returns error on push failure" do
      expect(Deploy.Git.Mock, :cmd, fn ["push" | _], _opts -> {"rejected", 1} end)

      args = %{workspace: "/tmp/ws", branch: "deploy-20260201"}
      assert {:error, msg} = Deploy.Reactors.Steps.GitPush.run(args, %{}, [])
      assert msg =~ "git push failed"
    end
  end

  describe "compensate/4" do
    test "deletes remote branch" do
      expect(Deploy.Git.Mock, :cmd, fn ["push", "origin", "--delete", "deploy-20260201"], _opts ->
        {"", 0}
      end)

      assert :ok =
               Deploy.Reactors.Steps.GitPush.compensate(
                 "deploy-20260201",
                 %{workspace: "/tmp/ws"},
                 %{},
                 []
               )
    end

    test "returns ok even when delete fails" do
      expect(Deploy.Git.Mock, :cmd, fn ["push", "origin", "--delete", _], _opts ->
        {"error", 1}
      end)

      assert :ok =
               Deploy.Reactors.Steps.GitPush.compensate(
                 "deploy-20260201",
                 %{workspace: "/tmp/ws"},
                 %{},
                 []
               )
    end
  end
end
