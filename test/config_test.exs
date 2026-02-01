defmodule Deploy.ConfigTest do
  use ExUnit.Case, async: true

  describe "repo_url/0" do
    test "returns env var value" do
      System.put_env("DEPLOY_REPO_URL", "https://github.com/acme/app.git")
      assert Deploy.Config.repo_url() == "https://github.com/acme/app.git"
    end

    test "raises when not set" do
      System.delete_env("DEPLOY_REPO_URL")
      assert_raise RuntimeError, ~r/DEPLOY_REPO_URL/, fn -> Deploy.Config.repo_url() end
    end
  end

  describe "github_token/0" do
    test "returns env var value" do
      System.put_env("GITHUB_TOKEN", "ghp_test123")
      assert Deploy.Config.github_token() == "ghp_test123"
    end

    test "raises when not set" do
      System.delete_env("GITHUB_TOKEN")
      assert_raise RuntimeError, ~r/GITHUB_TOKEN/, fn -> Deploy.Config.github_token() end
    end
  end

  describe "slack_webhook_url/0" do
    test "returns nil when not set" do
      System.delete_env("SLACK_WEBHOOK_URL")
      assert Deploy.Config.slack_webhook_url() == nil
    end

    test "returns value when set" do
      System.put_env("SLACK_WEBHOOK_URL", "https://hooks.slack.com/test")
      assert Deploy.Config.slack_webhook_url() == "https://hooks.slack.com/test"
    end
  end

  describe "github_owner/0 and github_repo/0" do
    setup do
      System.put_env("DEPLOY_REPO_URL", "https://github.com/myorg/myrepo.git")
      :ok
    end

    test "extracts owner from URL" do
      assert Deploy.Config.github_owner() == "myorg"
    end

    test "extracts repo name without .git" do
      assert Deploy.Config.github_repo() == "myrepo"
    end
  end

  describe "deploy_date/0" do
    test "returns today's date in YYYYMMDD format" do
      result = Deploy.Config.deploy_date()
      assert Regex.match?(~r/^\d{8}$/, result)
      assert result == Calendar.strftime(Date.utc_today(), "%Y%m%d")
    end
  end
end
