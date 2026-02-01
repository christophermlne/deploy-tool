defmodule Deploy.Reactors.Steps.ReturnMap do
  @moduledoc """
  Simple step that returns its arguments as a map.
  Used to aggregate results from multiple steps into a single return value.
  """

  use Reactor.Step

  @impl true
  def run(arguments, _context, _options) do
    {:ok, arguments}
  end

  @impl true
  def compensate(_result, _arguments, _context, _options), do: :ok
end
