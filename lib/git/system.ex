defmodule Deploy.Git.System do
  @moduledoc """
  Default git implementation using System.cmd.
  """

  @behaviour Deploy.Git

  @impl true
  def cmd(args, opts) do
    System.cmd("git", args, opts)
  end
end
