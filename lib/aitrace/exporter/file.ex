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
  - `:evidence_owner_ref` - Existing durable evidence owner that anchors this export

  ## File Format

  Files are named: `{trace_id}_{timestamp}.json`
  Evidence receipts are named: `{trace_id}_{timestamp}.evidence.json`

  Each file contains a JSON object with:
  - `trace_id` - The trace identifier
  - `metadata` - Trace metadata
  - `created_at` - Trace creation timestamp
  - `spans` - Array of all spans in the trace

  The adjacent evidence receipt contains the exported trace artifact SHA-256,
  byte count, release-manifest or evidence-owner linkage, and proof posture.
  """

  @behaviour AITrace.Exporter

  alias AITrace.{Clock, Event, Span, Trace}

  @schema_version "aitrace.file_export.v1"
  @evidence_schema_version "aitrace.file_export_evidence.v1"
  @proof_contexts ~w(audit incident replay review release_manifest)

  @impl true
  def init(opts) when is_list(opts) do
    init(Map.new(opts))
  end

  def init(opts) do
    directory = Map.get(opts, :directory, Map.get(opts, "directory", "./traces"))

    release_manifest_ref =
      Map.get(opts, :release_manifest_ref, Map.get(opts, "release_manifest_ref"))

    evidence_owner_ref = Map.get(opts, :evidence_owner_ref, Map.get(opts, "evidence_owner_ref"))

    # Create directory if it doesn't exist
    File.mkdir_p!(directory)

    state = %{
      directory: directory,
      release_manifest_ref: release_manifest_ref,
      evidence_owner_ref: evidence_owner_ref
    }

    {:ok, state}
  end

  @impl true
  def export(%Trace{} = trace, state) do
    exported_at_wall_time = Clock.wall_time_iso8601(Clock.wall_time())
    json = encode_trace(trace, state, exported_at_wall_time)
    filename = generate_filename(trace)
    file_path = Path.join(state.directory, filename)

    with :ok <- File.write(file_path, json),
         {:ok, evidence_receipt} <-
           write_evidence_receipt(trace, state, filename, json, exported_at_wall_time) do
      {:ok, Map.put(state, :last_export, evidence_receipt)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def shutdown(_state) do
    :ok
  end

  # Private functions

  defp encode_trace(%Trace{} = trace, state, exported_at_wall_time) do
    data = %{
      exporter_schema_version: @schema_version,
      release_manifest_ref: state.release_manifest_ref,
      exported_at_wall_time: exported_at_wall_time,
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

  defp write_evidence_receipt(
         %Trace{} = trace,
         state,
         trace_filename,
         trace_json,
         exported_at_wall_time
       ) do
    evidence_filename = evidence_filename(trace_filename)

    evidence_receipt =
      evidence_receipt(
        trace,
        state,
        trace_filename,
        evidence_filename,
        trace_json,
        exported_at_wall_time
      )

    evidence_path = Path.join(state.directory, evidence_filename)

    case File.write(evidence_path, Jason.encode!(evidence_receipt, pretty: true)) do
      :ok -> {:ok, evidence_receipt}
      {:error, reason} -> {:error, reason}
    end
  end

  defp evidence_receipt(
         %Trace{} = trace,
         state,
         trace_filename,
         evidence_filename,
         trace_json,
         exported_at_wall_time
       ) do
    %{
      evidence_schema_version: @evidence_schema_version,
      exporter_schema_version: @schema_version,
      trace_id: trace.trace_id,
      trace_id_source: trace.trace_id_source,
      trace_artifact_ref: trace_filename,
      evidence_receipt_ref: evidence_filename,
      trace_artifact_sha256: sha256(trace_json),
      trace_artifact_bytes: byte_size(trace_json),
      hash_algorithm: "sha256",
      release_manifest_ref: state.release_manifest_ref,
      evidence_owner_ref: state.evidence_owner_ref,
      exported_at_wall_time: exported_at_wall_time,
      proof_posture: proof_posture(state)
    }
  end

  defp proof_posture(state) do
    release_manifest_linked? = present_ref?(state.release_manifest_ref)
    evidence_owner_anchored? = present_ref?(state.evidence_owner_ref)
    authoritative_evidence? = release_manifest_linked? or evidence_owner_anchored?

    %{
      authoritative_evidence?: authoritative_evidence?,
      evidence_anchor: "durable_trace_artifact",
      release_manifest_linked?: release_manifest_linked?,
      evidence_owner_anchored?: evidence_owner_anchored?,
      proof_contexts: @proof_contexts,
      requires: [
        "durable_trace_artifact",
        "trace_artifact_sha256",
        "release_manifest_ref_or_evidence_owner_ref"
      ],
      safe_action: proof_safe_action(authoritative_evidence?)
    }
  end

  defp proof_safe_action(true), do: "cite_evidence_receipt"

  defp proof_safe_action(false),
    do: "release_manifest_ref_or_evidence_owner_ref_required_for_authoritative_proof"

  defp present_ref?(ref) when is_binary(ref), do: String.trim(ref) != ""
  defp present_ref?(_ref), do: false

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
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

  defp evidence_filename(trace_filename) do
    String.replace_suffix(trace_filename, ".json", ".evidence.json")
  end
end
