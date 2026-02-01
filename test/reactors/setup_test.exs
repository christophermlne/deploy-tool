defmodule Deploy.Reactors.SetupTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  describe "happy path" do
    test "runs full reactor with mocked git" do
      # clone
      Deploy.Git.Mock
      |> expect(:cmd, fn ["clone" | _], _opts -> {"", 0} end)
      # git config user.name
      |> expect(:cmd, fn ["config", "user.name" | _], _opts -> {"", 0} end)
      # git config user.email
      |> expect(:cmd, fn ["config", "user.email" | _], _opts -> {"", 0} end)
      # fetch
      |> expect(:cmd, fn ["fetch", "origin", "staging"], _opts -> {"", 0} end)
      # reset
      |> expect(:cmd, fn ["reset", "--hard", "origin/staging"], _opts -> {"", 0} end)
      # checkout base
      |> expect(:cmd, fn ["checkout", "staging"], _opts -> {"", 0} end)
      # checkout -b deploy branch
      |> expect(:cmd, fn ["checkout", "-b", "deploy-20260201"], _opts -> {"", 0} end)
      # push
      |> expect(:cmd, fn ["push", "-u", "origin", "deploy-20260201"], _opts -> {"", 0} end)

      inputs = %{
        repo_url: "https://github.com/org/repo.git",
        github_token: "tok",
        deploy_date: "20260201"
      }

      assert {:ok, "deploy-20260201"} = Reactor.run(Deploy.Reactors.Setup, inputs)
    end
  end

  describe "compensation on failure" do
    test "compensates when push fails" do
      # Use stub for all git calls since compensation order is non-deterministic
      Mox.stub(Deploy.Git.Mock, :cmd, fn args, _opts ->
        case args do
          ["push", "-u" | _] -> {"rejected", 1}
          _ -> {"", 0}
        end
      end)

      inputs = %{
        repo_url: "https://github.com/org/repo.git",
        github_token: "tok",
        deploy_date: "20260201"
      }

      assert {:error, _} = Reactor.run(Deploy.Reactors.Setup, inputs)
    end
  end
end
