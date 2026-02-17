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

  describe "update_branch/4" do
    test "returns ok on 202" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{"message" => "Updating"})
      end)

      assert {:ok, _} = Deploy.GitHub.update_branch(client, "o", "r", 1)
    end

    test "returns error on non-202" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"message" => "nope"})
      end)

      assert {:error, msg} = Deploy.GitHub.update_branch(client, "o", "r", 1)
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

  describe "list_prs/4" do
    test "returns ok with list of PRs" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, [%{"number" => 1, "title" => "PR 1"}, %{"number" => 2, "title" => "PR 2"}])
      end)

      assert {:ok, [%{"number" => 1}, %{"number" => 2}]} = Deploy.GitHub.list_prs(client, "o", "r")
    end

    test "passes base and state params" do
      client = stub_client(fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["base"] == "staging"
        assert query["state"] == "open"
        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = Deploy.GitHub.list_prs(client, "o", "r", base: "staging", state: "open")
    end

    test "returns error on non-200" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "error"})
      end)

      assert {:error, msg} = Deploy.GitHub.list_prs(client, "o", "r")
      assert msg =~ "500"
    end
  end

  describe "get_pr/4" do
    test "returns ok on 200" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"number" => 42, "title" => "My PR"})
      end)

      assert {:ok, %{"number" => 42}} = Deploy.GitHub.get_pr(client, "o", "r", 42)
    end

    test "returns error on non-200" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "not found"})
      end)

      assert {:error, msg} = Deploy.GitHub.get_pr(client, "o", "r", 99)
      assert msg =~ "404"
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

  describe "branch_exists?/4" do
    test "returns true on 200" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"name" => "deploy-20260217"})
      end)

      assert {:ok, true} = Deploy.GitHub.branch_exists?(client, "o", "r", "deploy-20260217")
    end

    test "returns false on 404" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Branch not found"})
      end)

      assert {:ok, false} = Deploy.GitHub.branch_exists?(client, "o", "r", "nonexistent")
    end

    test "returns error on other status" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "Server error"})
      end)

      assert {:error, msg} = Deploy.GitHub.branch_exists?(client, "o", "r", "branch")
      assert msg =~ "500"
    end
  end

  describe "list_merged_prs/4" do
    test "returns only merged PRs" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, [
          %{
            "number" => 1,
            "title" => "Merged PR",
            "merged_at" => "2026-02-17T10:00:00Z",
            "merge_commit_sha" => "abc123"
          },
          %{
            "number" => 2,
            "title" => "Closed but not merged",
            "merged_at" => nil,
            "merge_commit_sha" => nil
          }
        ])
      end)

      assert {:ok, merged} = Deploy.GitHub.list_merged_prs(client, "o", "r", "deploy-branch")
      assert length(merged) == 1
      assert hd(merged).number == 1
      assert hd(merged).title == "Merged PR"
      assert hd(merged).sha == "abc123"
    end

    test "passes base param for closed PRs" do
      client = stub_client(fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["state"] == "closed"
        assert query["base"] == "deploy-20260217"
        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = Deploy.GitHub.list_merged_prs(client, "o", "r", "deploy-20260217")
    end

    test "returns error on non-200" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "error"})
      end)

      assert {:error, msg} = Deploy.GitHub.list_merged_prs(client, "o", "r", "branch")
      assert msg =~ "500"
    end
  end

  describe "find_pr/5" do
    test "returns PR when found" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, [
          %{"number" => 99, "html_url" => "https://github.com/o/r/pull/99"}
        ])
      end)

      assert {:ok, %{number: 99, url: "https://github.com/o/r/pull/99"}} =
               Deploy.GitHub.find_pr(client, "o", "r", "deploy-20260217", "staging")
    end

    test "returns nil when no matching PR" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, [])
      end)

      assert {:ok, nil} = Deploy.GitHub.find_pr(client, "o", "r", "deploy-20260217", "staging")
    end

    test "passes correct query params" do
      client = stub_client(fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["state"] == "open"
        assert query["head"] == "owner:deploy-branch"
        assert query["base"] == "staging"
        Req.Test.json(conn, [])
      end)

      assert {:ok, nil} = Deploy.GitHub.find_pr(client, "owner", "repo", "deploy-branch", "staging")
    end

    test "returns error on non-200" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "error"})
      end)

      assert {:error, msg} = Deploy.GitHub.find_pr(client, "o", "r", "head", "base")
      assert msg =~ "500"
    end
  end

  describe "delete_branch/4" do
    test "returns ok on 204" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(204) |> Plug.Conn.send_resp(204, "")
      end)

      assert :ok = Deploy.GitHub.delete_branch(client, "o", "r", "branch-to-delete")
    end

    test "returns branch_not_found on 422" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"message" => "Reference does not exist"})
      end)

      assert {:error, :branch_not_found} = Deploy.GitHub.delete_branch(client, "o", "r", "nonexistent")
    end

    test "returns error on other status" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "Forbidden"})
      end)

      assert {:error, msg} = Deploy.GitHub.delete_branch(client, "o", "r", "protected-branch")
      assert msg =~ "403"
    end
  end

  describe "close_pr/4" do
    test "returns ok on 200" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"number" => 1, "state" => "closed"})
      end)

      assert {:ok, %{"state" => "closed"}} = Deploy.GitHub.close_pr(client, "o", "r", 1)
    end

    test "returns error on non-200" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not found"})
      end)

      assert {:error, msg} = Deploy.GitHub.close_pr(client, "o", "r", 999)
      assert msg =~ "404"
    end
  end

  describe "commit_in_branch?/5" do
    test "returns true when commit is ancestor of branch (status: ahead)" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"status" => "ahead", "ahead_by" => 5, "behind_by" => 0})
      end)

      assert {:ok, true} = Deploy.GitHub.commit_in_branch?(client, "o", "r", "abc123", "main")
    end

    test "returns true when commit is identical to branch HEAD" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"status" => "identical", "ahead_by" => 0, "behind_by" => 0})
      end)

      assert {:ok, true} = Deploy.GitHub.commit_in_branch?(client, "o", "r", "abc123", "main")
    end

    test "returns false when commit is not in branch (status: behind)" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"status" => "behind", "ahead_by" => 0, "behind_by" => 3})
      end)

      assert {:ok, false} = Deploy.GitHub.commit_in_branch?(client, "o", "r", "abc123", "main")
    end

    test "returns false when branches diverged" do
      client = stub_client(fn conn ->
        Req.Test.json(conn, %{"status" => "diverged", "ahead_by" => 2, "behind_by" => 3})
      end)

      assert {:ok, false} = Deploy.GitHub.commit_in_branch?(client, "o", "r", "abc123", "main")
    end

    test "returns false on 404 (commit or branch not found)" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert {:ok, false} = Deploy.GitHub.commit_in_branch?(client, "o", "r", "nonexistent", "main")
    end

    test "returns error on other status" do
      client = stub_client(fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "Server error"})
      end)

      assert {:error, msg} = Deploy.GitHub.commit_in_branch?(client, "o", "r", "abc123", "main")
      assert msg =~ "500"
    end
  end
end
