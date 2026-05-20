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
  - `:source_node_ref` - Stable node reference for per-node receipt discipline
  - `:node_instance_id`, `:boot_generation`, `:node_role`, `:deployment_ref` -
    optional node identity evidence
  - `:commit_lsn`, `:commit_hlc` - optional commit-order evidence to join
    receipts with proof tokens

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

  alias AITrace.{Clock, Event, ExportBounds, PersistencePosture, Span, Trace}
  alias AITrace.Trace.ReplayBundle

  @schema_version "aitrace.file_export.v1"
  @evidence_schema_version "aitrace.file_export_evidence.v1"
  @replay_bundle_schema_version "aitrace.replay_bundle_export.v1"
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

    node_evidence = node_evidence_from_opts(opts)

    state = %{
      directory: directory,
      release_manifest_ref: release_manifest_ref,
      evidence_owner_ref: evidence_owner_ref,
      source_node_ref: node_evidence[:source_node_ref],
      node_evidence: node_evidence,
      commit_lsn: get_opt(opts, :commit_lsn),
      commit_hlc: normalize_commit_hlc(get_opt(opts, :commit_hlc)),
      persistence_posture: PersistencePosture.resolve(:export, opts)
    }

    {:ok, state}
  end

  @impl true
  def export(%Trace{} = trace, state) do
    exported_at_wall_time = Clock.wall_time_iso8601(Clock.wall_time())
    json = encode_trace(trace, state, exported_at_wall_time)
    filename = generate_filename(trace)
    file_path = Path.join(state.directory, filename)

    with :ok <- prepare_directory(state.directory),
         :ok <- atomic_write(file_path, json),
         {:ok, evidence_receipt} <-
           write_evidence_receipt(trace, state, filename, json, exported_at_wall_time) do
      {:ok, Map.put(state, :last_export, evidence_receipt)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Writes a replay bundle into a replay-specific export directory with evidence.
  """
  @spec export_replay_bundle(ReplayBundle.t() | map(), map()) :: {:ok, map()} | {:error, term()}
  def export_replay_bundle(bundle_or_attrs, state) when is_map(state) do
    case normalize_replay_bundle(bundle_or_attrs) do
      {:ok, bundle} -> export_normalized_replay_bundle(bundle, state)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Verifies trace and replay bundle artifact/evidence pairs in an export directory.
  """
  @spec verify_export_directory(Path.t()) :: {:ok, map()} | {:error, map()}
  def verify_export_directory(directory) when is_binary(directory) do
    trace_exports = verify_pairs(directory)
    replay_bundles = verify_pairs(Path.join(directory, "replay_bundles"))

    report = %{
      complete?: complete_pairs?(trace_exports) and complete_pairs?(replay_bundles),
      trace_exports: trace_exports,
      replay_bundles: replay_bundles
    }

    if report.complete? do
      {:ok, report}
    else
      {:error, Map.put(report, :code, :incomplete_export_pairs)}
    end
  end

  @impl true
  def shutdown(_state) do
    :ok
  end

  # Private functions

  defp encode_trace(%Trace{} = trace, state, exported_at_wall_time) do
    data =
      %{
        exporter_schema_version: @schema_version,
        export_bounds: ExportBounds.profile(),
        export_persistence_posture:
          PersistencePosture.export_attributes(state.persistence_posture),
        trace_persistence_posture:
          PersistencePosture.export_attributes(trace.persistence_posture),
        replay_addressable?: trace.replay_addressable?,
        release_manifest_ref: state.release_manifest_ref,
        exported_at_wall_time: exported_at_wall_time,
        trace_id: trace.trace_id,
        trace_id_source: trace.trace_id_source,
        metadata: ExportBounds.bound_map!(trace.metadata, surface: :trace_metadata),
        created_at: trace.created_at,
        created_at_wall_time: Clock.wall_time_iso8601(trace.created_at_wall_time),
        clock_domain: trace.clock_domain,
        spans: Enum.map(trace.spans, &encode_span(&1, state.node_evidence))
      }
      |> maybe_put_node_evidence(state.node_evidence)
      |> maybe_put(:node_order_evidence, node_order_evidence(trace, state))

    Jason.encode!(data, pretty: true)
  end

  defp normalize_replay_bundle(%ReplayBundle{} = bundle), do: {:ok, bundle}
  defp normalize_replay_bundle(attrs) when is_map(attrs), do: ReplayBundle.new(attrs)
  defp normalize_replay_bundle(_attrs), do: {:error, :invalid_replay_bundle}

  defp source_trace_ref_present(%ReplayBundle{source_trace_ref: source_trace_ref}) do
    if present_ref?(source_trace_ref) do
      :ok
    else
      {:error, :missing_replay_source_trace_ref}
    end
  end

  defp export_normalized_replay_bundle(%ReplayBundle{} = bundle, state) do
    case source_trace_ref_present(bundle) do
      :ok -> write_replay_bundle(bundle, state)
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_replay_bundle(%ReplayBundle{} = bundle, state) do
    exported_at_wall_time = Clock.wall_time_iso8601(Clock.wall_time())
    replay_dir = Path.join(state.directory, "replay_bundles")
    json = encode_replay_bundle(bundle, state, exported_at_wall_time)
    filename = replay_bundle_filename(bundle)
    file_path = Path.join(replay_dir, filename)

    with :ok <- prepare_directory(replay_dir) do
      write_replay_bundle_file(file_path, bundle, state, filename, json, exported_at_wall_time)
    end
  end

  defp write_replay_bundle_file(file_path, bundle, state, filename, json, exported_at_wall_time) do
    case atomic_write(file_path, json) do
      :ok -> write_replay_bundle_evidence(bundle, state, filename, json, exported_at_wall_time)
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_replay_bundle(%ReplayBundle{} = bundle, state, exported_at_wall_time) do
    data =
      %{
        replay_bundle_schema_version: @replay_bundle_schema_version,
        export_bounds: ExportBounds.replay_divergence_excerpt_class(),
        exported_at_wall_time: exported_at_wall_time,
        release_manifest_ref: state.release_manifest_ref || bundle.release_manifest_ref,
        bundle_ref: bundle.bundle_ref,
        source_trace_ref: bundle.source_trace_ref,
        replay_trace_ref: bundle.replay_trace_ref,
        divergence_list_ref: bundle.divergence_list_ref,
        audit_ref: bundle.audit_ref,
        redaction_policy_ref: bundle.redaction_policy_ref,
        replay_persistence_posture:
          PersistencePosture.export_attributes(bundle.persistence_posture),
        export_persistence_posture:
          PersistencePosture.export_attributes(state.persistence_posture)
      }
      |> maybe_put_node_evidence(state.node_evidence)

    Jason.encode!(data, pretty: true)
  end

  defp write_replay_bundle_evidence(bundle, state, filename, json, exported_at_wall_time) do
    evidence_filename = String.replace_suffix(filename, ".json", ".evidence.json")

    receipt =
      %{
        evidence_schema_version: @evidence_schema_version,
        replay_bundle_schema_version: @replay_bundle_schema_version,
        bundle_ref: bundle.bundle_ref,
        replay_bundle_artifact_ref: filename,
        evidence_receipt_ref: evidence_filename,
        replay_bundle_artifact_sha256: sha256(json),
        replay_bundle_artifact_bytes: byte_size(json),
        hash_algorithm: "sha256",
        source_trace_ref: bundle.source_trace_ref,
        replay_trace_ref: bundle.replay_trace_ref,
        release_manifest_ref: state.release_manifest_ref || bundle.release_manifest_ref,
        replay_persistence_posture:
          PersistencePosture.export_attributes(bundle.persistence_posture),
        export_persistence_posture:
          PersistencePosture.export_attributes(state.persistence_posture),
        exported_at_wall_time: exported_at_wall_time,
        proof_posture: proof_posture(state)
      }
      |> maybe_put_node_evidence(state.node_evidence)

    evidence_path = Path.join([state.directory, "replay_bundles", evidence_filename])

    case atomic_write(evidence_path, Jason.encode!(receipt, pretty: true)) do
      :ok -> {:ok, receipt}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay_bundle_filename(%ReplayBundle{} = bundle) do
    bundle.bundle_ref
    |> safe_filename_component()
    |> then(&(&1 <> ".json"))
  end

  defp safe_filename_component(value) when is_binary(value) do
    value
    |> String.to_charlist()
    |> Enum.map(&safe_filename_char/1)
    |> List.to_string()
  end

  defp safe_filename_char(byte)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in [?_, ?., ?-],
       do: byte

  defp safe_filename_char(_byte), do: ?_

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

    case atomic_write(evidence_path, Jason.encode!(evidence_receipt, pretty: true)) do
      :ok -> {:ok, evidence_receipt}
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare_directory(directory), do: File.mkdir_p(directory)

  defp atomic_write(path, content) when is_binary(path) and is_binary(content) do
    tmp_path = temporary_path(path)

    case write_synced(tmp_path, content) do
      :ok ->
        rename_temporary(tmp_path, path)

      {:error, reason} ->
        cleanup_temporary(tmp_path)
        {:error, reason}
    end
  end

  defp write_synced(path, content) do
    case :file.open(String.to_charlist(path), [:write, :binary, :exclusive]) do
      {:ok, file} ->
        result =
          case :file.write(file, content) do
            :ok -> :file.sync(file)
            {:error, reason} -> {:error, reason}
          end

        close_result = :file.close(file)
        normalize_write_result(result, close_result)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_write_result(:ok, :ok), do: :ok
  defp normalize_write_result({:error, reason}, _close_result), do: {:error, reason}
  defp normalize_write_result(:ok, {:error, reason}), do: {:error, reason}

  defp rename_temporary(tmp_path, path) do
    case File.rename(tmp_path, path) do
      :ok ->
        :ok

      {:error, reason} ->
        cleanup_temporary(tmp_path)
        {:error, reason}
    end
  end

  defp cleanup_temporary(tmp_path) do
    _ = File.rm(tmp_path)
    :ok
  end

  defp temporary_path(path) do
    suffix = System.unique_integer([:positive, :monotonic])
    Path.join(Path.dirname(path), ".#{Path.basename(path)}.#{suffix}.tmp")
  end

  defp verify_pairs(directory) do
    files = listed_files(directory)
    artifact_files = artifact_files(files)
    evidence_files = evidence_files(files)

    %{
      complete?:
        missing_evidence_receipts(artifact_files, evidence_files) == [] and
          missing_trace_artifacts(artifact_files, evidence_files) == [],
      artifact_count: length(artifact_files),
      evidence_count: length(evidence_files),
      missing_evidence_receipts: missing_evidence_receipts(artifact_files, evidence_files),
      missing_trace_artifacts: missing_trace_artifacts(artifact_files, evidence_files)
    }
  end

  defp listed_files(directory) do
    case File.ls(directory) do
      {:ok, files} -> Enum.reject(files, &temporary_file?/1)
      {:error, :enoent} -> []
      {:error, _reason} -> []
    end
  end

  defp artifact_files(files) do
    files
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.reject(&String.ends_with?(&1, ".evidence.json"))
    |> Enum.sort()
  end

  defp evidence_files(files) do
    files
    |> Enum.filter(&String.ends_with?(&1, ".evidence.json"))
    |> Enum.sort()
  end

  defp missing_evidence_receipts(artifact_files, evidence_files) do
    Enum.reject(artifact_files, fn filename ->
      evidence_filename(filename) in evidence_files
    end)
  end

  defp missing_trace_artifacts(artifact_files, evidence_files) do
    Enum.reject(evidence_files, fn filename ->
      trace_filename_from_evidence(filename) in artifact_files
    end)
  end

  defp trace_filename_from_evidence(filename) do
    String.replace_suffix(filename, ".evidence.json", ".json")
  end

  defp temporary_file?(filename) do
    String.starts_with?(filename, ".") and String.ends_with?(filename, ".tmp")
  end

  defp complete_pairs?(%{complete?: complete?}), do: complete?

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
      trace_persistence_posture: PersistencePosture.export_attributes(trace.persistence_posture),
      export_persistence_posture: PersistencePosture.export_attributes(state.persistence_posture),
      exported_at_wall_time: exported_at_wall_time,
      proof_posture: proof_posture(state)
    }
    |> maybe_put_node_evidence(state.node_evidence)
    |> maybe_put(:node_order_evidence, node_order_evidence(trace, state))
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
      requires: proof_requirements(state),
      safe_action: proof_safe_action(authoritative_evidence?)
    }
  end

  defp proof_requirements(state) do
    base = [
      "durable_trace_artifact",
      "trace_artifact_sha256",
      "release_manifest_ref_or_evidence_owner_ref"
    ]

    if present_ref?(state.source_node_ref) do
      base ++ ["source_node_ref", "trace_id_plus_node_order_evidence"]
    else
      base
    end
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

  defp encode_span(%Span{} = span, node_evidence) do
    span_source_node_ref = span_source_node_ref(span, node_evidence)

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
      persistence_posture: PersistencePosture.export_attributes(span.persistence_posture),
      attributes: ExportBounds.bound_map!(span.attributes, surface: :span_attributes),
      events: Enum.map(span.events, &encode_event/1),
      status: span.status
    }
    |> maybe_put(:source_node_ref, span_source_node_ref)
  end

  defp encode_event(%Event{} = event) do
    %{
      name: event.name,
      timestamp: event.timestamp,
      wall_time: Clock.wall_time_iso8601(event.wall_time),
      clock_domain: event.clock_domain,
      persistence_posture: PersistencePosture.export_attributes(event.persistence_posture),
      attributes: ExportBounds.bound_map!(event.attributes, surface: :event_attributes)
    }
  end

  defp generate_filename(%Trace{} = trace) do
    timestamp = System.system_time(:second)
    "#{trace.trace_id}_#{timestamp}.json"
  end

  defp evidence_filename(trace_filename) do
    String.replace_suffix(trace_filename, ".json", ".evidence.json")
  end

  defp node_evidence_from_opts(opts) do
    %{
      source_node_ref: normalize_ref(get_opt(opts, :source_node_ref), :source_node_ref),
      node_instance_id: normalize_ref(get_opt(opts, :node_instance_id), :node_instance_id),
      boot_generation: normalize_boot_generation(get_opt(opts, :boot_generation)),
      node_role: normalize_ref(get_opt(opts, :node_role), :node_role),
      deployment_ref: normalize_ref(get_opt(opts, :deployment_ref), :deployment_ref),
      cluster_ref: normalize_ref(get_opt(opts, :cluster_ref), :cluster_ref)
    }
    |> reject_nil_values()
  end

  defp node_order_evidence(%Trace{} = trace, state) do
    if present_ref?(state.source_node_ref) do
      %{
        trace_id: trace.trace_id,
        source_node_ref: state.source_node_ref,
        commit_lsn: state.commit_lsn,
        commit_hlc: state.commit_hlc
      }
      |> reject_nil_values()
    end
  end

  defp maybe_put_node_evidence(data, node_evidence) when map_size(node_evidence) == 0, do: data

  defp maybe_put_node_evidence(data, node_evidence) do
    data
    |> maybe_put(:source_node_ref, node_evidence[:source_node_ref])
    |> Map.put(:node_evidence, node_evidence)
  end

  defp span_source_node_ref(%Span{} = span, node_evidence) do
    Map.get(span.attributes, :source_node_ref) ||
      Map.get(span.attributes, "source_node_ref") ||
      node_evidence[:source_node_ref]
  end

  defp get_opt(opts, key) do
    Map.get(opts, key, Map.get(opts, Atom.to_string(key)))
  end

  defp normalize_ref(nil, _key), do: nil

  defp normalize_ref(value, key) when is_binary(value) do
    if String.trim(value) == "" do
      raise ArgumentError, "file_exporter.#{key} must be a non-empty string"
    end

    value
  end

  defp normalize_ref(value, key) do
    raise ArgumentError, "file_exporter.#{key} must be a string, got: #{inspect(value)}"
  end

  defp normalize_boot_generation(nil), do: nil

  defp normalize_boot_generation(value) when is_integer(value) and value > 0, do: value

  defp normalize_boot_generation(value) do
    raise ArgumentError,
          "file_exporter.boot_generation must be a positive integer, got: #{inspect(value)}"
  end

  defp normalize_commit_hlc(nil), do: nil

  defp normalize_commit_hlc(value) when is_map(value) do
    value
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp normalize_commit_hlc(value) do
    raise ArgumentError, "file_exporter.commit_hlc must be a map, got: #{inspect(value)}"
  end

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp maybe_put(data, _key, nil), do: data
  defp maybe_put(data, key, value), do: Map.put(data, key, value)
end
