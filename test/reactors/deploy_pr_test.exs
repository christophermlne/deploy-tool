defmodule Deploy.Reactors.DeployPRTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  defp stub_client(plug), do: Req.new(plug: plug)

  setup do
    # Create a temporary workspace with version files
    workspace = Path.join(System.tmp_dir!(), "deploy_pr_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    File.mkdir_p!(Path.join(workspace, "backend"))
    File.mkdir_p!(Path.join(workspace, "frontend"))

    File.write!(Path.join(workspace, "version.txt"), "2.4.10")
    File.write!(Path.join(workspace, "backend/version.txt"), "2.4.10")
    File.write!(Path.join(workspace, "frontend/package.json"), ~s|{"name": "app", "version": "2.4.10"}|)

    on_exit(fn -> File.rm_rf!(workspace) end)

    %{workspace: workspace}
  end

  defp stub_git_for_version_bump(workspace) do
    Mox.stub(Deploy.Git.Mock, :cmd, fn args, opts ->
      assert opts[:cd] == workspace

      case args do
        ["add" | _] -> {"", 0}
        ["commit", "-m", msg] when is_binary(msg) -> {"", 0}
        ["rev-parse", "HEAD"] -> {"abc123def\n", 0}
        ["push", "origin", _branch] -> {"", 0}
        _ -> {"", 0}
      end
    end)
  end

  test "full reactor: bumps version, creates PR, updates description, skips review", %{workspace: workspace} do
    stub_git_for_version_bump(workspace)

    client = stub_client(fn conn ->
      case {conn.method, conn.path_info} do
        {"POST", ["repos", "o", "r", "pulls"]} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"number" => 99, "html_url" => "https://github.com/o/r/pull/99"})

        {"PATCH", ["repos", "o", "r", "pulls", "99"]} ->
          Req.Test.json(conn, %{"number" => 99})
      end
    end)

    inputs = %{
      workspace: workspace,
      deploy_branch: "deploy-20260201",
      merged_prs: [%{number: 1, title: "Feature A", sha: "aaa"}],
      client: client,
      owner: "o",
      repo: "r",
      reviewers: []
    }

    assert {:ok, %{number: 99, url: "https://github.com/o/r/pull/99"}} =
             Reactor.run(Deploy.Reactors.DeployPR, inputs)

    # Verify version was bumped
    assert File.read!(Path.join(workspace, "version.txt")) == "2.4.11"
  end

  test "full reactor with reviewers", %{workspace: workspace} do
    stub_git_for_version_bump(workspace)

    client = stub_client(fn conn ->
      case {conn.method, conn.path_info} do
        {"POST", ["repos", "o", "r", "pulls"]} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"number" => 99, "html_url" => "https://github.com/o/r/pull/99"})

        {"PATCH", ["repos", "o", "r", "pulls", "99"]} ->
          Req.Test.json(conn, %{"number" => 99})

        {"POST", ["repos", "o", "r", "pulls", "99", "requested_reviewers"]} ->
          conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 1})
      end
    end)

    inputs = %{
      workspace: workspace,
      deploy_branch: "deploy-20260201",
      merged_prs: [%{number: 1, title: "Feature", sha: "aaa"}],
      client: client,
      owner: "o",
      repo: "r",
      reviewers: ["alice"]
    }

    assert {:ok, %{number: 99}} = Reactor.run(Deploy.Reactors.DeployPR, inputs)
  end

  test "PR description contains only PR numbers", %{workspace: workspace} do
    stub_git_for_version_bump(workspace)

    client = stub_client(fn conn ->
      case {conn.method, conn.path_info} do
        {"POST", ["repos", "o", "r", "pulls"]} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"number" => 99, "html_url" => "https://github.com/o/r/pull/99"})

        {"PATCH", ["repos", "o", "r", "pulls", "99"]} ->
          {:ok, body, _} = Plug.Conn.read_body(conn)
          decoded = Jason.decode!(body)
          # Verify simplified format
          assert decoded["body"] == "#2654\n#2378\n#2401"
          Req.Test.json(conn, %{"number" => 99})
      end
    end)

    inputs = %{
      workspace: workspace,
      deploy_branch: "deploy-20260201",
      merged_prs: [
        %{number: 2654, title: "Feature A", sha: "aaa"},
        %{number: 2378, title: "Feature B", sha: "bbb"},
        %{number: 2401, title: "Feature C", sha: "ccc"}
      ],
      client: client,
      owner: "o",
      repo: "r",
      reviewers: []
    }

    assert {:ok, _} = Reactor.run(Deploy.Reactors.DeployPR, inputs)
  end
end
