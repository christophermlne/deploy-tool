defmodule Deploy.Git do
  @moduledoc """
  Behaviour for git operations, allowing test mocking.
  """

  @callback cmd(args :: [String.t()], opts :: keyword()) :: {String.t(), non_neg_integer()}

  def cmd(args, opts \\ []) do
    impl().cmd(args, opts)
  end

  defp impl do
    Application.get_env(:deploy, :git_module, Deploy.Git.System)
  end
end
