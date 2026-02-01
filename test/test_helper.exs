Mox.defmock(Deploy.Git.Mock, for: Deploy.Git)
Application.put_env(:deploy, :git_module, Deploy.Git.Mock)

ExUnit.start()
