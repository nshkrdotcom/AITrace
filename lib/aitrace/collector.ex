defmodule AITrace.Collector do
  @moduledoc """
  In-memory collector for traces in progress.

  The Collector stores active traces and allows updating them as spans
  and events are added during execution.
  """

  use Agent

  alias AITrace.{Trace, Span}

  @doc """
  Starts the collector agent.
  """
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Creates a new trace and stores it.
  """
  @spec new_trace(String.t()) :: Trace.t()
  def new_trace(trace_id) do
    trace = Trace.new(trace_id)

    Agent.update(__MODULE__, fn traces ->
      Map.put(traces, trace_id, trace)
    end)

    trace
  end

  @doc """
  Retrieves a trace by its trace_id.
  """
  @spec get_trace(String.t()) :: Trace.t() | nil
  def get_trace(trace_id) do
    Agent.get(__MODULE__, fn traces ->
      Map.get(traces, trace_id)
    end)
  end

  @doc """
  Adds a span to a trace.
  """
  @spec add_span(String.t(), Span.t()) :: :ok
  def add_span(trace_id, %Span{} = span) do
    Agent.update(__MODULE__, fn traces ->
      case Map.get(traces, trace_id) do
        nil ->
          traces

        trace ->
          updated_trace = Trace.add_span(trace, span)
          Map.put(traces, trace_id, updated_trace)
      end
    end)
  end

  @doc """
  Updates a span within a trace.
  """
  @spec update_span(String.t(), String.t(), (Span.t() -> Span.t())) :: :ok
  def update_span(trace_id, span_id, update_fn) do
    Agent.update(__MODULE__, fn traces ->
      case Map.get(traces, trace_id) do
        nil ->
          traces

        trace ->
          updated_spans =
            Enum.map(trace.spans, fn span ->
              if span.span_id == span_id do
                update_fn.(span)
              else
                span
              end
            end)

          updated_trace = %{trace | spans: updated_spans}
          Map.put(traces, trace_id, updated_trace)
      end
    end)
  end

  @doc """
  Removes a trace from the collector.
  """
  @spec remove_trace(String.t()) :: :ok
  def remove_trace(trace_id) do
    Agent.update(__MODULE__, fn traces ->
      Map.delete(traces, trace_id)
    end)
  end

  @doc """
  Clears all traces from the collector.
  """
  @spec clear() :: :ok
  def clear do
    # Start agent if not already started
    case Process.whereis(__MODULE__) do
      nil -> start_link([])
      _pid -> :ok
    end

    Agent.update(__MODULE__, fn _traces -> %{} end)
  end
end
