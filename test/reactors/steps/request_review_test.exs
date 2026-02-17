defmodule Deploy.Reactors.Steps.RequestReviewTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.RequestReview

  defp stub_client(plug), do: Req.new(plug: plug)

  test "skips when reviewers is empty" do
    arguments = %{reviewers: []}

    assert {:ok, :skipped} = RequestReview.run(arguments, %{}, [])
  end

  test "requests review when reviewers provided" do
    client = stub_client(fn conn ->
      conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 1})
    end)

    arguments = %{
      client: client,
      owner: "o",
      repo: "r",
      pr_number: 99,
      reviewers: ["alice", "bob"]
    }

    assert {:ok, _} = RequestReview.run(arguments, %{}, [])
  end
end
