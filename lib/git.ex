defmodule Deploy.Git do
  @moduledoc """
  Behaviour for git operations, allowing test mocking.
  """

  @callback cmd(args :: [String.t()], opts :: keyword()) :: {String.t(), non_neg_integer()}

  def cmd(args, opts \\ []) do
    impl().cmd(args, opts)
  end

  @doc """
  Runs a git command and returns :ok on success or {:error, message} on failure.
  """
  def run!(args, opts \\ []) do
    case cmd(args, opts) do
      {_output, 0} -> :ok
      {output, code} -> {:error, "git #{hd(args)} failed (exit #{code}): #{output}"}
    end
  end

  defp impl do
    Application.get_env(:deploy, :git_module, Deploy.Git.System)
  end
end
