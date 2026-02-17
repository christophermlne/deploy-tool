defmodule Deploy.Reactors.Steps.CreateDeployPRTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.CreateDeployPR

  defp stub_client(plug), do: Req.new(plug: plug)

  test "creates PR with formatted title" do
    client = stub_client(fn conn ->
      {:ok, body, _} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["title"] == "Deploy 2026-02-01"
      assert decoded["head"] == "deploy-20260201"
      assert decoded["base"] == "staging"

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"number" => 99, "html_url" => "https://github.com/o/r/pull/99"})
    end)

    arguments = %{client: client, owner: "o", repo: "r", deploy_branch: "deploy-20260201"}

    assert {:ok, %{number: 99, url: "https://github.com/o/r/pull/99"}} =
             CreateDeployPR.run(arguments, %{}, [])
  end

  test "returns error on failure" do
    client = stub_client(fn conn ->
      conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"message" => "nope"})
    end)

    arguments = %{client: client, owner: "o", repo: "r", deploy_branch: "deploy-20260201"}

    assert {:error, _} = CreateDeployPR.run(arguments, %{}, [])
  end

  test "compensation closes the PR" do
    client = stub_client(fn conn ->
      {:ok, body, _} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["state"] == "closed"
      Req.Test.json(conn, %{"number" => 99, "state" => "closed"})
    end)

    result = %{number: 99, url: "https://github.com/o/r/pull/99"}
    arguments = %{client: client, owner: "o", repo: "r"}

    assert :ok = CreateDeployPR.compensate(result, arguments, %{}, [])
  end
end
