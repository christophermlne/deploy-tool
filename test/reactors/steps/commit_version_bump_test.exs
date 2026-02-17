defmodule Deploy.Reactors.Steps.CommitVersionBumpTest do
  use ExUnit.Case, async: false

  import Mox

  alias Deploy.Reactors.Steps.CommitVersionBump

  setup :verify_on_exit!

  describe "run/3" do
    test "stages files and commits with version message" do
      Deploy.Git.Mock
      |> expect(:cmd, fn ["add", "version.txt", "backend/version.txt", "frontend/package.json"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)
      |> expect(:cmd, fn ["commit", "-m", "Bump version to 2.4.11"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)
      |> expect(:cmd, fn ["rev-parse", "HEAD"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"abc123def456\n", 0}
      end)

      args = %{workspace: "/tmp/ws", new_version: "2.4.11"}
      assert {:ok, "abc123def456"} = CommitVersionBump.run(args, %{}, [])
    end

    test "returns error on git add failure" do
      expect(Deploy.Git.Mock, :cmd, fn ["add" | _], _opts -> {"error", 1} end)

      args = %{workspace: "/tmp/ws", new_version: "2.4.11"}
      assert {:error, msg} = CommitVersionBump.run(args, %{}, [])
      assert msg =~ "Failed to commit version bump"
    end

    test "returns error on git commit failure" do
      Deploy.Git.Mock
      |> expect(:cmd, fn ["add" | _], _opts -> {"", 0} end)
      |> expect(:cmd, fn ["commit" | _], _opts -> {"nothing to commit", 1} end)

      args = %{workspace: "/tmp/ws", new_version: "2.4.11"}
      assert {:error, msg} = CommitVersionBump.run(args, %{}, [])
      assert msg =~ "Failed to commit version bump"
    end
  end

  describe "compensate/4" do
    test "resets to HEAD~1" do
      expect(Deploy.Git.Mock, :cmd, fn ["reset", "--hard", "HEAD~1"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)

      args = %{workspace: "/tmp/ws", new_version: "2.4.11"}
      assert :ok = CommitVersionBump.compensate("abc123", args, %{}, [])
    end

    test "returns ok even when reset fails" do
      expect(Deploy.Git.Mock, :cmd, fn ["reset", "--hard", "HEAD~1"], _opts ->
        {"error", 1}
      end)

      args = %{workspace: "/tmp/ws", new_version: "2.4.11"}
      assert :ok = CommitVersionBump.compensate("abc123", args, %{}, [])
    end
  end
end
