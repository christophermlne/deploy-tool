defmodule Deploy.Reactors.DeployPRTest do
  use ExUnit.Case, async: true

  defp stub_client(plug), do: Req.new(plug: plug)

  test "full reactor: creates PR, updates description, skips review" do
    client = stub_client(fn conn ->
      case {conn.method, conn.path_info} do
        # create_deploy_pr: POST /repos/o/r/pulls
        {"POST", ["repos", "o", "r", "pulls"]} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"number" => 99, "html_url" => "https://github.com/o/r/pull/99"})

        # update_pr_description: PATCH /repos/o/r/pulls/99
        {"PATCH", ["repos", "o", "r", "pulls", "99"]} ->
          Req.Test.json(conn, %{"number" => 99})
      end
    end)

    inputs = %{
      deploy_branch: "deploy-20260201",
      merged_prs: [%{number: 1, title: "Feature A", sha: "aaa"}],
      client: client,
      owner: "o",
      repo: "r",
      reviewers: []
    }

    assert {:ok, %{number: 99, url: "https://github.com/o/r/pull/99"}} =
             Reactor.run(Deploy.Reactors.DeployPR, inputs)
  end

  test "full reactor with reviewers" do
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
      deploy_branch: "deploy-20260201",
      merged_prs: [%{number: 1, title: "Feature", sha: "aaa"}],
      client: client,
      owner: "o",
      repo: "r",
      reviewers: ["alice"]
    }

    assert {:ok, %{number: 99}} = Reactor.run(Deploy.Reactors.DeployPR, inputs)
  end
end
