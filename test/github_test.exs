defmodule Deploy.GitHubTest do
  use ExUnit.Case, async: true

  defp stub_client(plug) do
    Req.new(plug: plug)
  end

  describe "change_pr_base/5" do
    test "returns ok on 200" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"number" => 1, "base" => %{"ref" => "deploy-branch"}})
      end)

      assert {:ok, %{"number" => 1}} = Deploy.GitHub.change_pr_base(client, "o", "r", 1, "deploy-branch")
    end

    test "returns error on non-200" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"message" => "nope"})
      end)

      assert {:error, msg} = Deploy.GitHub.change_pr_base(client, "o", "r", 1, "x")
      assert msg =~ "422"
    end
  end

  describe "merge_pr/5" do
    test "returns ok on 200" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"merged" => true})
      end)

      assert {:ok, %{"merged" => true}} = Deploy.GitHub.merge_pr(client, "o", "r", 1)
    end

    test "passes merge_method and commit_title" do
      client = stub_client(fn conn ->
        {:ok, body, _} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["merge_method"] == "merge"
        assert decoded["commit_title"] == "my title"
        Req.Test.json(conn, %{"merged" => true})
      end)

      assert {:ok, _} = Deploy.GitHub.merge_pr(client, "o", "r", 1, merge_method: "merge", commit_title: "my title")
    end
  end

  describe "create_pr/4" do
    test "returns ok on 201" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"number" => 42})
      end)

      assert {:ok, %{"number" => 42}} =
               Deploy.GitHub.create_pr(client, "o", "r", %{title: "t", head: "h", base: "b"})
    end
  end

  describe "update_pr/5" do
    test "returns ok on 200" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"number" => 1})
      end)

      assert {:ok, _} = Deploy.GitHub.update_pr(client, "o", "r", 1, %{title: "new"})
    end
  end

  describe "get_check_runs/4" do
    test "returns ok on 200" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"check_runs" => []})
      end)

      assert {:ok, %{"check_runs" => []}} = Deploy.GitHub.get_check_runs(client, "o", "r", "abc123")
    end
  end

  describe "ci_status/4" do
    test "pending when no runs" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"check_runs" => []})
      end)

      assert {:ok, :pending} = Deploy.GitHub.ci_status(client, "o", "r", "ref")
    end

    test "pending when runs not completed" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"check_runs" => [%{"status" => "in_progress", "conclusion" => nil}]})
      end)

      assert {:ok, :pending} = Deploy.GitHub.ci_status(client, "o", "r", "ref")
    end

    test "success when all pass" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"check_runs" => [%{"status" => "completed", "conclusion" => "success"}]})
      end)

      assert {:ok, :success} = Deploy.GitHub.ci_status(client, "o", "r", "ref")
    end

    test "failed when some fail" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{
          "check_runs" => [
            %{"status" => "completed", "conclusion" => "success"},
            %{"status" => "completed", "conclusion" => "failure"}
          ]
        })
      end)

      assert {:ok, {:failed, [_]}} = Deploy.GitHub.ci_status(client, "o", "r", "ref")
    end
  end

  describe "request_review/5" do
    test "returns ok on 201" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 1})
      end)

      assert {:ok, _} = Deploy.GitHub.request_review(client, "o", "r", 1, ["user1"])
    end
  end

  describe "pr_approved?/4" do
    test "true when approved and no changes requested" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, [
          %{"user" => %{"login" => "a"}, "state" => "APPROVED", "submitted_at" => "2026-01-01T00:00:00Z"}
        ])
      end)

      assert {:ok, true} = Deploy.GitHub.pr_approved?(client, "o", "r", 1)
    end

    test "false when changes requested" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, [
          %{"user" => %{"login" => "a"}, "state" => "APPROVED", "submitted_at" => "2026-01-01T00:00:00Z"},
          %{"user" => %{"login" => "b"}, "state" => "CHANGES_REQUESTED", "submitted_at" => "2026-01-01T00:00:00Z"}
        ])
      end)

      assert {:ok, false} = Deploy.GitHub.pr_approved?(client, "o", "r", 1)
    end

    test "uses latest review per user" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, [
          %{"user" => %{"login" => "a"}, "state" => "CHANGES_REQUESTED", "submitted_at" => "2026-01-01T00:00:00Z"},
          %{"user" => %{"login" => "a"}, "state" => "APPROVED", "submitted_at" => "2026-01-02T00:00:00Z"}
        ])
      end)

      assert {:ok, true} = Deploy.GitHub.pr_approved?(client, "o", "r", 1)
    end
  end

  describe "get_release_by_tag/4" do
    test "returns ok on 200" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"id" => 1, "tag_name" => "v1.0"})
      end)

      assert {:ok, %{"id" => 1}} = Deploy.GitHub.get_release_by_tag(client, "o", "r", "v1.0")
    end

    test "returns not_found on 404" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})
      end)

      assert {:error, :not_found} = Deploy.GitHub.get_release_by_tag(client, "o", "r", "v1.0")
    end
  end

  describe "update_release/5" do
    test "returns ok on 200" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"id" => 1})
      end)

      assert {:ok, _} = Deploy.GitHub.update_release(client, "o", "r", 1, "new body")
    end
  end
end
