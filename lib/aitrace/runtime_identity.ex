defmodule AITrace.RuntimeIdentity do
  @moduledoc """
  Supervised owner for immutable runtime identity evidence.

  The runtime id is generated when this process starts and remains stable for
  that supervised process lifetime. Tests can start scoped owners under custom
  names instead of mutating VM-global state.
  """

  use GenServer

  @type snapshot :: %{
          runtime_id: String.t(),
          node: String.t(),
          booted_at_wall_time: DateTime.t()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec runtime_id(GenServer.server()) :: String.t()
  def runtime_id(owner \\ __MODULE__) do
    owner
    |> snapshot()
    |> Map.fetch!(:runtime_id)
  end

  @spec snapshot(GenServer.server()) :: snapshot()
  def snapshot(owner \\ __MODULE__) do
    GenServer.call(owner, :snapshot)
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       runtime_id: Keyword.get_lazy(opts, :runtime_id, &generate_runtime_id/0),
       node: Atom.to_string(node()),
       booted_at_wall_time: DateTime.utc_now()
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  defp generate_runtime_id do
    "#{node()}:#{System.system_time(:nanosecond)}:#{System.unique_integer([:positive])}"
  end
end
