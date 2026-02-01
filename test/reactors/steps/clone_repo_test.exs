defmodule Deploy.Reactors.Steps.CloneRepoTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  describe "run/3" do
    test "clones repo and configures git user on success" do
      Deploy.Git.Mock
      |> expect(:cmd, fn ["clone", "--depth", "1", "--branch", "staging", url, "."], opts ->
        assert String.contains?(url, "tok123@")
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)
      |> expect(:cmd, fn ["config", "user.name", "Deploy Bot"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)
      |> expect(:cmd, fn ["config", "user.email", "deploy-bot@example.com"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)

      args = %{workspace: "/tmp/ws", repo_url: "https://github.com/org/repo.git", github_token: "tok123"}
      assert {:ok, "/tmp/ws"} = Deploy.Reactors.Steps.CloneRepo.run(args, %{}, [])
    end

    test "returns error on clone failure with redacted token" do
      Deploy.Git.Mock
      |> expect(:cmd, fn ["clone" | _], _opts ->
        {"fatal: could not connect tok123", 128}
      end)

      args = %{workspace: "/tmp/ws", repo_url: "https://github.com/org/repo.git", github_token: "tok123"}
      assert {:error, msg} = Deploy.Reactors.Steps.CloneRepo.run(args, %{}, [])
      assert msg =~ "[REDACTED]"
      refute msg =~ "tok123"
    end
  end

  describe "compensate/4" do
    test "returns ok" do
      assert :ok = Deploy.Reactors.Steps.CloneRepo.compensate("/tmp/ws", %{}, %{}, [])
    end
  end
end
