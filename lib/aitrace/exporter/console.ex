defmodule AITrace.Exporter.Console do
  @moduledoc """
  Console exporter for human-readable trace output.

  This exporter prints traces to stdout in a formatted, readable way.
  Perfect for local development and debugging.

  ## Options

  - `:verbose` - Show detailed attributes and events (default: false)
  - `:color` - Use ANSI color codes (default: false)
  """

  @behaviour AITrace.Exporter

  alias AITrace.{Trace, Span, Event}

  @impl true
  def init(opts) when is_list(opts) do
    init(Map.new(opts))
  end

  def init(opts) when is_map(opts) do
    state = %{
      verbose: Map.get(opts, :verbose, false),
      color: Map.get(opts, :color, false)
    }

    {:ok, state}
  end

  @impl true
  def export(%Trace{} = trace, state) do
    IO.puts("\n" <> header("Trace: #{trace.trace_id}", state))

    if map_size(trace.metadata) > 0 and state.verbose do
      IO.puts("  Metadata: #{inspect(trace.metadata)}")
    end

    root_spans = Trace.get_root_spans(trace)

    Enum.each(root_spans, fn span ->
      print_span(span, trace, state, 0)
    end)

    IO.puts("")
    {:ok, state}
  end

  @impl true
  def shutdown(_state) do
    :ok
  end

  # Private functions

  defp print_span(%Span{} = span, trace, state, depth) do
    indent = String.duplicate("  ", depth)
    duration_str = format_duration(Span.duration(span))
    status_str = format_status(span.status, state)

    IO.puts("#{indent}▸ #{span.name} #{duration_str} #{status_str}")

    if state.verbose and map_size(span.attributes) > 0 do
      IO.puts("#{indent}  Attributes: #{inspect(span.attributes)}")
    end

    if state.verbose and length(span.events) > 0 do
      Enum.each(span.events, fn event ->
        print_event(event, state, depth + 1)
      end)
    end

    children = Trace.get_children(trace, span.span_id)

    Enum.each(children, fn child ->
      print_span(child, trace, state, depth + 1)
    end)
  end

  defp print_event(%Event{} = event, _state, depth) do
    indent = String.duplicate("  ", depth)
    IO.puts("#{indent}  • #{event.name}")

    if map_size(event.attributes) > 0 do
      IO.puts("#{indent}    #{inspect(event.attributes)}")
    end
  end

  defp format_duration(nil), do: "(in progress)"

  defp format_duration(microseconds) when is_integer(microseconds) do
    cond do
      microseconds < 1_000 ->
        "(#{microseconds}μs)"

      microseconds < 1_000_000 ->
        "(#{Float.round(microseconds / 1_000, 2)}ms)"

      true ->
        "(#{Float.round(microseconds / 1_000_000, 2)}s)"
    end
  end

  defp format_status(:ok, _state), do: "✓"
  defp format_status(:error, _state), do: "✗"
  defp format_status(_, _state), do: ""

  defp header(text, %{color: true}) do
    # Bold cyan
    "\e[1m\e[36m#{text}\e[0m"
  end

  defp header(text, _state), do: text
end
