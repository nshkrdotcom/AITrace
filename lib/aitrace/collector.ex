defmodule AITrace.Collector do
  @moduledoc """
  Supervised in-memory collector for traces in progress.

  The collector stores active traces in one supervised owner per trace id. This
  state is working memory only; exported traces remain the authoritative proof
  path.
  """

  use Supervisor

  alias AITrace.{Collector.TraceOwner, Span, Trace}

  @collector_supervisor __MODULE__.Supervisor
  @collector_registry __MODULE__.Registry

  @doc """
  Starts the collector supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: @collector_registry},
      {DynamicSupervisor, strategy: :one_for_one, name: @collector_supervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Creates a new trace owner and stores the trace.
  """
  @spec new_trace(String.t(), keyword()) :: Trace.t()
  def new_trace(trace_id, opts \\ []) do
    child_spec = {TraceOwner, Keyword.put(opts, :trace_id, trace_id)}

    case DynamicSupervisor.start_child(@collector_supervisor, child_spec) do
      {:ok, _pid} -> get_trace(trace_id)
      {:error, {:already_started, _pid}} -> get_trace(trace_id)
    end
  end

  @doc """
  Retrieves a trace by its trace_id.
  """
  @spec get_trace(String.t()) :: Trace.t() | nil
  def get_trace(trace_id) do
    case owner(trace_id) do
      {:ok, pid} -> safe_call(fn -> TraceOwner.get(pid) end, nil)
      :error -> nil
    end
  end

  @doc """
  Adds a span to a trace.
  """
  @spec add_span(String.t(), Span.t()) :: :ok | {:error, map()}
  def add_span(trace_id, %Span{} = span) do
    case owner(trace_id) do
      {:ok, pid} -> safe_call(fn -> TraceOwner.add_span(pid, span) end, :ok)
      :error -> :ok
    end
  end

  @doc """
  Updates a span within a trace.
  """
  @spec update_span(String.t(), String.t(), (Span.t() -> Span.t())) :: :ok
  def update_span(trace_id, span_id, update_fn) when is_function(update_fn, 1) do
    case owner(trace_id) do
      {:ok, pid} -> safe_call(fn -> TraceOwner.update_span(pid, span_id, update_fn) end, :ok)
      :error -> :ok
    end
  end

  @doc """
  Removes a trace owner from the collector.
  """
  @spec remove_trace(String.t()) :: :ok
  def remove_trace(trace_id) do
    with {:ok, pid} <- owner(trace_id) do
      DynamicSupervisor.terminate_child(@collector_supervisor, pid)
    end

    :ok
  end

  @doc """
  Clears all traces from the supervised collector.
  """
  @spec clear() :: :ok | {:error, :collector_not_started}
  def clear do
    case Process.whereis(@collector_supervisor) do
      nil ->
        {:error, :collector_not_started}

      _pid ->
        @collector_supervisor
        |> DynamicSupervisor.which_children()
        |> Enum.each(fn {_id, pid, _type, _modules} ->
          DynamicSupervisor.terminate_child(@collector_supervisor, pid)
        end)

        :ok
    end
  end

  @doc false
  @spec owner_pid(String.t()) :: pid() | nil
  def owner_pid(trace_id) do
    case owner(trace_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  @doc """
  Returns per-trace collector stats.
  """
  @spec stats(String.t()) :: map() | nil
  def stats(trace_id) do
    case owner(trace_id) do
      {:ok, pid} -> safe_call(fn -> TraceOwner.stats(pid) end, nil)
      :error -> nil
    end
  end

  @doc """
  Returns false because collector state is in-memory working state only.
  """
  @spec authoritative_evidence?() :: false
  def authoritative_evidence?, do: false

  @doc """
  Describes the collector evidence posture for release and incident proof.
  """
  @spec evidence_posture() :: map()
  def evidence_posture do
    %{
      storage: :supervised_trace_owners,
      authoritative_evidence?: false,
      safe_action: :export_required_for_authoritative_evidence
    }
  end

  defp owner(trace_id) do
    case Registry.lookup(@collector_registry, trace_id) do
      [{pid, _value}] -> alive_owner(pid)
      [] -> :error
    end
  end

  defp alive_owner(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: :error
  end

  defp safe_call(fun, fallback) do
    fun.()
  catch
    :exit, _reason -> fallback
  end
end
