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
  - `:release_manifest_ref` - Release manifest or evidence bundle reference for this export

  ## File Format

  Files are named: `{trace_id}_{timestamp}.json`

  Each file contains a JSON object with:
  - `trace_id` - The trace identifier
  - `metadata` - Trace metadata
  - `created_at` - Trace creation timestamp
  - `spans` - Array of all spans in the trace
  """

  @behaviour AITrace.Exporter

  alias AITrace.{Clock, Event, Span, Trace}

  @schema_version "aitrace.file_export.v1"

  @impl true
  def init(opts) when is_list(opts) do
    init(Map.new(opts))
  end

  def init(opts) do
    directory = Map.get(opts, :directory, Map.get(opts, "directory", "./traces"))

    release_manifest_ref =
      Map.get(opts, :release_manifest_ref, Map.get(opts, "release_manifest_ref"))

    # Create directory if it doesn't exist
    File.mkdir_p!(directory)

    state = %{directory: directory, release_manifest_ref: release_manifest_ref}
    {:ok, state}
  end

  @impl true
  def export(%Trace{} = trace, state) do
    json = encode_trace(trace, state)
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

  defp encode_trace(%Trace{} = trace, state) do
    data = %{
      exporter_schema_version: @schema_version,
      release_manifest_ref: state.release_manifest_ref,
      exported_at_wall_time: Clock.wall_time_iso8601(Clock.wall_time()),
      trace_id: trace.trace_id,
      trace_id_source: trace.trace_id_source,
      metadata: trace.metadata,
      created_at: trace.created_at,
      created_at_wall_time: Clock.wall_time_iso8601(trace.created_at_wall_time),
      clock_domain: trace.clock_domain,
      spans: Enum.map(trace.spans, &encode_span/1)
    }

    Jason.encode!(data, pretty: true)
  end

  defp encode_span(%Span{} = span) do
    %{
      span_id: span.span_id,
      span_id_source: span.span_id_source,
      parent_span_id: span.parent_span_id,
      parent_span_id_source: span.parent_span_id_source,
      name: span.name,
      start_time: span.start_time,
      start_wall_time: Clock.wall_time_iso8601(span.start_wall_time),
      end_time: span.end_time,
      end_wall_time: Clock.wall_time_iso8601(span.end_wall_time),
      duration_microseconds: Span.duration(span),
      clock_domain: span.clock_domain,
      attributes: span.attributes,
      events: Enum.map(span.events, &encode_event/1),
      status: span.status
    }
  end

  defp encode_event(%Event{} = event) do
    %{
      name: event.name,
      timestamp: event.timestamp,
      wall_time: Clock.wall_time_iso8601(event.wall_time),
      clock_domain: event.clock_domain,
      attributes: event.attributes
    }
  end

  defp generate_filename(%Trace{} = trace) do
    timestamp = System.system_time(:second)
    "#{trace.trace_id}_#{timestamp}.json"
  end
end
