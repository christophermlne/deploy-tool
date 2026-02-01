defmodule Deploy.Reactors.Steps.GitFetchTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  describe "run/3" do
    test "fetches and resets on success" do
      Deploy.Git.Mock
      |> expect(:cmd, fn ["fetch", "origin", "staging"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)
      |> expect(:cmd, fn ["reset", "--hard", "origin/staging"], opts ->
        assert opts[:cd] == "/tmp/ws"
        {"", 0}
      end)

      args = %{workspace: "/tmp/ws", branch: "staging"}
      assert {:ok, "staging"} = Deploy.Reactors.Steps.GitFetch.run(args, %{}, [])
    end

    test "returns error when fetch fails" do
      expect(Deploy.Git.Mock, :cmd, fn ["fetch" | _], _opts -> {"error", 1} end)

      args = %{workspace: "/tmp/ws", branch: "staging"}
      assert {:error, msg} = Deploy.Reactors.Steps.GitFetch.run(args, %{}, [])
      assert msg =~ "Git fetch failed"
    end

    test "returns error when reset fails" do
      Deploy.Git.Mock
      |> expect(:cmd, fn ["fetch" | _], _opts -> {"", 0} end)
      |> expect(:cmd, fn ["reset" | _], _opts -> {"error", 1} end)

      args = %{workspace: "/tmp/ws", branch: "staging"}
      assert {:error, msg} = Deploy.Reactors.Steps.GitFetch.run(args, %{}, [])
      assert msg =~ "Git reset failed"
    end
  end
end
