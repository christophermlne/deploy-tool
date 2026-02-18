defmodule Deploy.Deployments.Supervisor do
  @moduledoc """
  DynamicSupervisor for deployment runner processes.

  Each deployment execution runs as a supervised GenServer child.
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new deployment runner process.
  """
  @spec start_runner(keyword()) :: DynamicSupervisor.on_start_child()
  def start_runner(opts) do
    spec = {Deploy.Deployments.Runner, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stops a deployment runner process.
  """
  @spec stop_runner(pid()) :: :ok | {:error, :not_found}
  def stop_runner(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  Lists all running deployment processes.
  """
  @spec list_runners() :: [pid()]
  def list_runners do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end
end
