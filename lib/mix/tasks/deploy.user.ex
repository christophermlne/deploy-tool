defmodule Mix.Tasks.Deploy.User do
  @moduledoc """
  Manage users for the deploy web interface.

  ## Commands

  ### Create a user

      mix deploy.user create USERNAME [--display-name "Name"]

  Creates a new user. You will be prompted for a password.

  ### List users

      mix deploy.user list [--all]

  Lists active users by default. Use `--all` to include inactive users.

  ### Deactivate a user

      mix deploy.user deactivate USERNAME

  Deactivates a user account (they can no longer log in).

  ### Reset password

      mix deploy.user reset_password USERNAME

  Resets a user's password. You will be prompted for a new password.
  """

  use Mix.Task

  @shortdoc "Manage deploy tool users"

  @switches [
    display_name: :string,
    all: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    case args do
      ["create", username | rest] -> create_user(username, rest)
      ["list" | rest] -> list_users(rest)
      ["deactivate", username] -> deactivate_user(username)
      ["reset_password", username] -> reset_password(username)
      _ -> usage()
    end
  end

  defp create_user(username, rest) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(rest, switches: @switches)

    password = prompt_password("Enter password: ")
    confirm = prompt_password("Confirm password: ")

    if password != confirm do
      Mix.shell().error("Passwords do not match")
      exit({:shutdown, 1})
    end

    if String.length(password) < 8 do
      Mix.shell().error("Password must be at least 8 characters")
      exit({:shutdown, 1})
    end

    attrs = %{
      username: username,
      password: password,
      display_name: opts[:display_name] || username
    }

    case Deploy.Accounts.create_user(attrs) do
      {:ok, user} ->
        Mix.shell().info("Created user: #{user.username}")

      {:error, changeset} ->
        errors = format_errors(changeset)
        Mix.shell().error("Failed to create user: #{errors}")
        exit({:shutdown, 1})
    end
  end

  defp list_users(rest) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(rest, switches: @switches)
    filter = if opts[:all], do: [], else: [active: true]

    users = Deploy.Accounts.list_users(filter)

    if Enum.empty?(users) do
      Mix.shell().info("No users found.")
    else
      Mix.shell().info("Users:")

      for user <- users do
        status = if user.active, do: "", else: " (inactive)"
        Mix.shell().info("  #{user.username}#{status} - #{user.display_name || "(no display name)"}")
      end

      Mix.shell().info("")
      Mix.shell().info("Total: #{length(users)} user(s)")
    end
  end

  defp deactivate_user(username) do
    Mix.Task.run("app.start")

    case Deploy.Accounts.get_user_by_username(username) do
      nil ->
        Mix.shell().error("User not found: #{username}")
        exit({:shutdown, 1})

      user ->
        if not user.active do
          Mix.shell().info("User is already inactive: #{username}")
        else
          {:ok, _} = Deploy.Accounts.deactivate_user(user)
          Mix.shell().info("Deactivated user: #{username}")
        end
    end
  end

  defp reset_password(username) do
    Mix.Task.run("app.start")

    case Deploy.Accounts.get_user_by_username(username) do
      nil ->
        Mix.shell().error("User not found: #{username}")
        exit({:shutdown, 1})

      user ->
        password = prompt_password("New password: ")
        confirm = prompt_password("Confirm: ")

        if password != confirm do
          Mix.shell().error("Passwords do not match")
          exit({:shutdown, 1})
        end

        if String.length(password) < 8 do
          Mix.shell().error("Password must be at least 8 characters")
          exit({:shutdown, 1})
        end

        case Deploy.Accounts.change_user_password(user, %{password: password}) do
          {:ok, _} ->
            Mix.shell().info("Password reset for: #{username}")

          {:error, changeset} ->
            errors = format_errors(changeset)
            Mix.shell().error("Failed to reset password: #{errors}")
            exit({:shutdown, 1})
        end
    end
  end

  defp usage do
    Mix.shell().info("""
    Usage:
      mix deploy.user create USERNAME [--display-name "Name"]
      mix deploy.user list [--all]
      mix deploy.user deactivate USERNAME
      mix deploy.user reset_password USERNAME

    Run `mix help deploy.user` for more information.
    """)
  end

  defp prompt_password(prompt) do
    # Note: This will show the password in the terminal.
    # For production, consider using :io.get_password/0 which hides input.
    Mix.shell().prompt(prompt) |> String.trim()
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end
end
