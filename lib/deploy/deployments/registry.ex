defmodule Deploy.Deployments.Registry do
  @moduledoc """
  GenServer that tracks active deployment processes in memory.

  Maps deployment_id => pid for currently running deployments.
  Monitors processes to automatically clean up when they exit.
  """

  use GenServer

  @type deployment_id :: integer()

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register a deployment process.

  Returns `:ok` if registration succeeds, or `{:error, :already_registered}` if
  the deployment is already being tracked.
  """
  @spec register(deployment_id(), pid()) :: :ok | {:error, :already_registered}
  def register(deployment_id, pid \\ self()) do
    GenServer.call(__MODULE__, {:register, deployment_id, pid})
  end

  @doc """
  Unregister a deployment process.
  """
  @spec unregister(deployment_id()) :: :ok
  def unregister(deployment_id) do
    GenServer.call(__MODULE__, {:unregister, deployment_id})
  end

  @doc """
  Look up the pid for a deployment.

  Returns `{:ok, pid}` if found, or `:error` if not found.
  """
  @spec lookup(deployment_id()) :: {:ok, pid()} | :error
  def lookup(deployment_id) do
    GenServer.call(__MODULE__, {:lookup, deployment_id})
  end

  @doc """
  List all active deployments.

  Returns a list of `{deployment_id, pid}` tuples.
  """
  @spec list_active() :: [{deployment_id(), pid()}]
  def list_active do
    GenServer.call(__MODULE__, :list_active)
  end

  @doc """
  Check if a deployment is currently active.
  """
  @spec is_active?(deployment_id()) :: boolean()
  def is_active?(deployment_id) do
    case lookup(deployment_id) do
      {:ok, _pid} -> true
      :error -> false
    end
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # State: %{deployment_id => {pid, monitor_ref}}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, deployment_id, pid}, _from, state) do
    if Map.has_key?(state, deployment_id) do
      {:reply, {:error, :already_registered}, state}
    else
      ref = Process.monitor(pid)
      {:reply, :ok, Map.put(state, deployment_id, {pid, ref})}
    end
  end

  def handle_call({:unregister, deployment_id}, _from, state) do
    case Map.pop(state, deployment_id) do
      {{_pid, ref}, new_state} ->
        Process.demonitor(ref, [:flush])
        {:reply, :ok, new_state}

      {nil, state} ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:lookup, deployment_id}, _from, state) do
    case Map.get(state, deployment_id) do
      {pid, _ref} -> {:reply, {:ok, pid}, state}
      nil -> {:reply, :error, state}
    end
  end

  def handle_call(:list_active, _from, state) do
    active = Enum.map(state, fn {deployment_id, {pid, _ref}} -> {deployment_id, pid} end)
    {:reply, active, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Find and remove the deployment that just exited
    new_state =
      state
      |> Enum.reject(fn {_deployment_id, {_pid, monitor_ref}} -> monitor_ref == ref end)
      |> Map.new()

    {:noreply, new_state}
  end
end
