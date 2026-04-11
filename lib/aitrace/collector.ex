defmodule AITrace.Collector do
  @moduledoc """
  In-memory collector for traces in progress.

  The Collector stores active traces and allows updating them as spans
  and events are added during execution.
  """

  use Agent

  alias AITrace.{Span, Trace}

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
      update_trace(traces, trace_id, &Trace.add_span(&1, span))
    end)
  end

  @doc """
  Updates a span within a trace.
  """
  @spec update_span(String.t(), String.t(), (Span.t() -> Span.t())) :: :ok
  def update_span(trace_id, span_id, update_fn) do
    Agent.update(__MODULE__, fn traces ->
      update_trace(traces, trace_id, fn trace ->
        updated_spans = Enum.map(trace.spans, &maybe_update_span(&1, span_id, update_fn))
        %{trace | spans: updated_spans}
      end)
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

  defp update_trace(traces, trace_id, update_fn) do
    case Map.fetch(traces, trace_id) do
      {:ok, trace} -> Map.put(traces, trace_id, update_fn.(trace))
      :error -> traces
    end
  end

  defp maybe_update_span(%Span{span_id: span_id} = span, span_id, update_fn), do: update_fn.(span)
  defp maybe_update_span(%Span{} = span, _span_id, _update_fn), do: span
end
