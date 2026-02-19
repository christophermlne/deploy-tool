defmodule Deploy.Reactors.StepMapper do
  @moduledoc """
  Introspects reactor composition to build step-to-phase mappings.

  Uses Spark's DSL introspection to derive which steps belong to which
  composed reactor, enabling automatic grouping in the UI without
  hard-coding step names.
  """

  @doc """
  Builds a map of step names to their parent reactor names.

  ## Example

      iex> StepMapper.build_step_mapping(Deploy.Reactors.FullDeploy)
      %{
        "create_workspace" => "setup",
        "clone_repo" => "setup",
        "fetch_approved_prs" => "merge_prs",
        ...
      }
  """
  @spec build_step_mapping(module()) :: %{String.t() => String.t()}
  def build_step_mapping(reactor_module) do
    config = reactor_module.spark_dsl_config()
    entities = get_in(config, [[:reactor], :entities]) || []

    entities
    |> Enum.filter(&match?(%{__struct__: Reactor.Dsl.Compose}, &1))
    |> Enum.flat_map(fn compose ->
      phase_name = Atom.to_string(compose.name)
      steps = get_reactor_steps(compose.reactor)
      Enum.map(steps, fn step_name -> {step_name, phase_name} end)
    end)
    |> Map.new()
  end

  @doc """
  Returns the ordered list of compose phases for a reactor.

  The order matches the definition order in the reactor module.

  ## Example

      iex> StepMapper.get_phase_order(Deploy.Reactors.FullDeploy)
      ["setup", "merge_prs", "deploy_pr"]
  """
  @spec get_phase_order(module()) :: [String.t()]
  def get_phase_order(reactor_module) do
    config = reactor_module.spark_dsl_config()
    entities = get_in(config, [[:reactor], :entities]) || []

    entities
    |> Enum.filter(&match?(%{__struct__: Reactor.Dsl.Compose}, &1))
    |> Enum.map(&Atom.to_string(&1.name))
  end

  defp get_reactor_steps(reactor_module) do
    config = reactor_module.spark_dsl_config()
    entities = get_in(config, [[:reactor], :entities]) || []

    entities
    |> Enum.filter(&match?(%{__struct__: Reactor.Dsl.Step}, &1))
    |> Enum.map(&Atom.to_string(&1.name))
  end
end
