defmodule AITrace.Collector.TraceOwner do
  @moduledoc false

  use GenServer

  alias AITrace.{Span, Telemetry, Trace}

  @default_max_spans_per_trace 10_000

  @type stats :: %{
          span_count: non_neg_integer(),
          dropped_spans: non_neg_integer(),
          max_spans: pos_integer()
        }

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    trace_id = Keyword.fetch!(opts, :trace_id)

    %{
      id: {__MODULE__, trace_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5_000,
      type: :worker
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    trace_id = Keyword.fetch!(opts, :trace_id)
    GenServer.start_link(__MODULE__, opts, name: via(trace_id))
  end

  @spec via(String.t()) :: {:via, Registry, {AITrace.Collector.Registry, String.t()}}
  def via(trace_id), do: {:via, Registry, {AITrace.Collector.Registry, trace_id}}

  @spec get(pid()) :: Trace.t()
  def get(pid), do: GenServer.call(pid, :get)

  @spec add_span(pid(), Span.t()) :: :ok | {:error, map()}
  def add_span(pid, %Span{} = span), do: GenServer.call(pid, {:add_span, span})

  @spec update_span(pid(), String.t(), (Span.t() -> Span.t())) :: :ok
  def update_span(pid, span_id, update_fn) when is_function(update_fn, 1) do
    GenServer.call(pid, {:update_span, span_id, update_fn})
  end

  @spec stats(pid()) :: stats()
  def stats(pid), do: GenServer.call(pid, :stats)

  @impl true
  def init(opts) do
    trace_id = Keyword.fetch!(opts, :trace_id)
    max_spans = Keyword.get(opts, :max_spans_per_trace, @default_max_spans_per_trace)

    {:ok,
     %{
       trace: Trace.new(trace_id, id_source: :aitrace_generated),
       max_spans: max_spans,
       dropped_spans: 0
     }}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state.trace, state}

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       span_count: length(state.trace.spans),
       dropped_spans: state.dropped_spans,
       max_spans: state.max_spans
     }, state}
  end

  def handle_call({:add_span, %Span{} = span}, _from, state) do
    if length(state.trace.spans) >= state.max_spans do
      dropped_spans = state.dropped_spans + 1

      Telemetry.execute(
        [:aitrace, :collector, :span, :dropped],
        %{count: 1, dropped_spans: dropped_spans},
        %{
          trace_id: state.trace.trace_id,
          span_id: span.span_id,
          reason: :capacity_exceeded,
          max_spans: state.max_spans
        }
      )

      {:reply,
       {:error,
        %{
          code: :capacity_exceeded,
          dropped_spans: dropped_spans,
          max_spans: state.max_spans
        }}, %{state | dropped_spans: dropped_spans}}
    else
      {:reply, :ok, %{state | trace: Trace.add_span(state.trace, span)}}
    end
  end

  def handle_call({:update_span, span_id, update_fn}, _from, state) do
    updated_spans = Enum.map(state.trace.spans, &maybe_update_span(&1, span_id, update_fn))
    {:reply, :ok, %{state | trace: %{state.trace | spans: updated_spans}}}
  end

  defp maybe_update_span(%Span{span_id: span_id} = span, span_id, update_fn), do: update_fn.(span)
  defp maybe_update_span(%Span{} = span, _span_id, _update_fn), do: span
end
