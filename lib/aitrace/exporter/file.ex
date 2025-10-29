defmodule AITrace.Exporter.File do
  @moduledoc """
  File exporter that writes traces to JSON files.

  This exporter is useful for:
  - Permanent trace storage
  - Post-mortem debugging
  - Trace analysis with external tools
  - Building trace datasets

  ## Options

  - `:directory` - Directory to write trace files (default: "./traces")

  ## File Format

  Files are named: `{trace_id}_{timestamp}.json`

  Each file contains a JSON object with:
  - `trace_id` - The trace identifier
  - `metadata` - Trace metadata
  - `created_at` - Trace creation timestamp
  - `spans` - Array of all spans in the trace
  """

  @behaviour AITrace.Exporter

  alias AITrace.{Trace, Span, Event}

  @impl true
  def init(opts) do
    directory = Map.get(opts, :directory, "./traces")

    # Create directory if it doesn't exist
    File.mkdir_p!(directory)

    state = %{directory: directory}
    {:ok, state}
  end

  @impl true
  def export(%Trace{} = trace, state) do
    json = encode_trace(trace)
    filename = generate_filename(trace)
    file_path = Path.join(state.directory, filename)

    case File.write(file_path, json) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def shutdown(_state) do
    :ok
  end

  # Private functions

  defp encode_trace(%Trace{} = trace) do
    data = %{
      trace_id: trace.trace_id,
      metadata: trace.metadata,
      created_at: trace.created_at,
      spans: Enum.map(trace.spans, &encode_span/1)
    }

    Jason.encode!(data, pretty: true)
  end

  defp encode_span(%Span{} = span) do
    %{
      span_id: span.span_id,
      parent_span_id: span.parent_span_id,
      name: span.name,
      start_time: span.start_time,
      end_time: span.end_time,
      attributes: span.attributes,
      events: Enum.map(span.events, &encode_event/1),
      status: span.status
    }
  end

  defp encode_event(%Event{} = event) do
    %{
      name: event.name,
      timestamp: event.timestamp,
      attributes: event.attributes
    }
  end

  defp generate_filename(%Trace{} = trace) do
    timestamp = System.system_time(:second)
    "#{trace.trace_id}_#{timestamp}.json"
  end
end
