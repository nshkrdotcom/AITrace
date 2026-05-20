defmodule AITrace.Exporter.FileTest do
  use ExUnit.Case, async: true

  alias AITrace.{Event, Exporter.File, Span, Trace}

  setup do
    test_dir =
      Path.join(System.tmp_dir!(), "aitrace_file_test_#{System.unique_integer([:positive])}")

    Elixir.File.rm_rf!(test_dir)
    Elixir.File.mkdir_p!(test_dir)

    on_exit(fn ->
      Elixir.File.rm_rf!(test_dir)
    end)

    {:ok, test_dir: test_dir}
  end

  describe "init/1" do
    test "accepts keyword-list options", %{test_dir: test_dir} do
      assert {:ok, state} =
               File.init(
                 directory: test_dir,
                 release_manifest_ref: "release:phase5",
                 evidence_owner_ref: "evidence-owner:trace-file"
               )

      assert state.directory == test_dir
      assert state.release_manifest_ref == "release:phase5"
      assert state.evidence_owner_ref == "evidence-owner:trace-file"
    end

    test "initializes with directory path", %{test_dir: test_dir} do
      opts = %{directory: test_dir, release_manifest_ref: "release:map"}
      assert {:ok, state} = File.init(opts)
      assert state.directory == test_dir
      assert state.release_manifest_ref == "release:map"
    end

    test "init validates config without creating export directory", %{test_dir: test_dir} do
      dir = Path.join(test_dir, "new_dir")
      refute :filelib.is_dir(String.to_charlist(dir))

      {:ok, _state} = File.init(%{directory: dir})

      refute :filelib.is_dir(String.to_charlist(dir))
    end

    test "defaults to ./traces directory" do
      {:ok, state} = File.init(%{})
      assert state.directory == "./traces"
    end
  end

  describe "export/2" do
    test "writes trace to JSON file", %{test_dir: test_dir} do
      {:ok, state} =
        File.init(%{directory: test_dir, release_manifest_ref: "release:phase5-v7-m5"})

      trace = Trace.new("test_trace_123")
      span = Span.new("operation") |> Span.finish()
      trace = Trace.add_span(trace, span)

      {:ok, _state} = File.export(trace, state)

      assert length(exported_files(test_dir)) == 2
      data = read_json!(trace_file_path!(test_dir))

      assert data["trace_id"] == "test_trace_123"
      assert data["exporter_schema_version"] == "aitrace.file_export.v1"
      assert data["release_manifest_ref"] == "release:phase5-v7-m5"

      assert data["trace_persistence_posture"]["capture_level_ref"] ==
               "capture-level://redacted-memory-ring"

      assert data["export_persistence_posture"]["raw_payload_persistence?"] == false
      assert is_binary(data["created_at_wall_time"])
      assert data["clock_domain"]["monotonic_unit"] == "microsecond"
      assert is_list(data["spans"])
      assert length(data["spans"]) == 1
    end

    test "creates export directory at export time", %{test_dir: test_dir} do
      dir = Path.join(test_dir, "created_on_export")
      {:ok, state} = File.init(%{directory: dir})

      refute :filelib.is_dir(String.to_charlist(dir))

      assert {:ok, _state} = File.export(Trace.new("trace_created_on_export"), state)
      assert :filelib.is_dir(String.to_charlist(dir))
      assert length(exported_files(dir)) == 2
    end

    test "failed export leaves no final or temporary trace artifact", %{test_dir: test_dir} do
      blocked_parent = Path.join(test_dir, "not_a_directory")
      Elixir.File.write!(blocked_parent, "blocks child directory creation")
      blocked_dir = Path.join(blocked_parent, "child")
      {:ok, state} = File.init(%{directory: blocked_dir})

      assert {:error, :enotdir} = File.export(Trace.new("trace_write_failure"), state)
      assert Elixir.File.ls!(test_dir) == ["not_a_directory"]
    end

    test "writes durable evidence receipt with content hash and release-manifest linkage", %{
      test_dir: test_dir
    } do
      {:ok, state} =
        File.init(%{
          directory: test_dir,
          release_manifest_ref: "release:phase5-v7-m5",
          evidence_owner_ref: "evidence-owner:trace-file"
        })

      trace = Trace.new("trace_with_evidence")
      span = Span.new("operation") |> Span.finish()
      trace = Trace.add_span(trace, span)

      assert {:ok, %{last_export: last_export}} = File.export(trace, state)

      trace_path = trace_file_path!(test_dir)
      evidence_path = evidence_file_path!(test_dir)
      trace_json = Elixir.File.read!(trace_path)
      evidence = read_json!(evidence_path)

      assert evidence["evidence_schema_version"] == "aitrace.file_export_evidence.v1"
      assert evidence["exporter_schema_version"] == "aitrace.file_export.v1"
      assert evidence["trace_id"] == "trace_with_evidence"
      assert evidence["trace_artifact_ref"] == Path.basename(trace_path)
      assert evidence["evidence_receipt_ref"] == Path.basename(evidence_path)
      assert evidence["trace_artifact_sha256"] == sha256(trace_json)
      assert evidence["trace_artifact_bytes"] == byte_size(trace_json)
      assert evidence["hash_algorithm"] == "sha256"
      assert evidence["release_manifest_ref"] == "release:phase5-v7-m5"
      assert evidence["evidence_owner_ref"] == "evidence-owner:trace-file"
      assert evidence["trace_persistence_posture"]["raw_payload_persistence?"] == false

      assert evidence["export_persistence_posture"]["capture_level_ref"] ==
               "capture-level://redacted-memory-ring"

      assert evidence["proof_posture"]["authoritative_evidence?"] == true
      assert evidence["proof_posture"]["release_manifest_linked?"] == true
      assert evidence["proof_posture"]["evidence_owner_anchored?"] == true
      assert evidence["proof_posture"]["safe_action"] == "cite_evidence_receipt"

      assert last_export.trace_artifact_sha256 == sha256(trace_json)
      assert last_export.release_manifest_ref == "release:phase5-v7-m5"
    end

    test "directory verifier reports missing evidence receipt", %{test_dir: test_dir} do
      {:ok, state} = File.init(%{directory: test_dir})

      assert {:ok, _state} = File.export(Trace.new("trace_missing_evidence"), state)
      evidence_path = evidence_file_path!(test_dir)
      Elixir.File.rm!(evidence_path)

      assert {:error, report} = File.verify_export_directory(test_dir)
      assert report.code == :incomplete_export_pairs

      assert report.trace_exports.missing_evidence_receipts == [
               Path.basename(trace_file_path!(test_dir))
             ]

      assert report.trace_exports.missing_trace_artifacts == []
    end

    test "directory verifier reports missing trace artifact", %{test_dir: test_dir} do
      {:ok, state} = File.init(%{directory: test_dir})

      assert {:ok, _state} = File.export(Trace.new("trace_missing_artifact"), state)
      trace_path = trace_file_path!(test_dir)
      Elixir.File.rm!(trace_path)

      assert {:error, report} = File.verify_export_directory(test_dir)
      assert report.code == :incomplete_export_pairs
      assert report.trace_exports.missing_evidence_receipts == []

      assert report.trace_exports.missing_trace_artifacts == [
               Path.basename(evidence_file_path!(test_dir))
             ]
    end

    test "exports replay bundle with evidence and verifier coverage", %{test_dir: test_dir} do
      {:ok, state} =
        File.init(%{
          directory: test_dir,
          release_manifest_ref: "release:replay-bundle",
          evidence_owner_ref: "evidence-owner:replay"
        })

      bundle = replay_bundle("bundle-phase57-replay")

      assert {:ok, receipt} = File.export_replay_bundle(bundle, state)
      replay_dir = Path.join(test_dir, "replay_bundles")

      assert ["bundle-phase57-replay.evidence.json", "bundle-phase57-replay.json"] =
               Enum.sort(exported_files(replay_dir))

      bundle_json = Elixir.File.read!(Path.join(replay_dir, "bundle-phase57-replay.json"))
      evidence = read_json!(Path.join(replay_dir, "bundle-phase57-replay.evidence.json"))

      assert evidence["replay_bundle_artifact_sha256"] == sha256(bundle_json)
      assert receipt.replay_bundle_artifact_sha256 == sha256(bundle_json)
      assert {:ok, %{complete?: true}} = File.verify_export_directory(test_dir)
    end

    test "embeds per-node receipt and span evidence for multi-node joins", %{test_dir: test_dir} do
      commit_hlc = %{
        "w" => 1_776_947_200_000_000_000,
        "l" => 2,
        "n" => "node://aitrace_1@127.0.0.1/node-a"
      }

      {:ok, state} =
        File.init(%{
          directory: test_dir,
          release_manifest_ref: "release:phase7-m7a",
          evidence_owner_ref: "evidence-owner:aitrace-node-a",
          source_node_ref: "node://aitrace_1@127.0.0.1/node-a",
          node_instance_id: "node-instance-a",
          boot_generation: 3,
          node_role: "stacklab_probe",
          deployment_ref: "deployment://phase7/local",
          commit_lsn: "16/B374D848",
          commit_hlc: commit_hlc
        })

      trace =
        Trace.new("trace_node_a")
        |> Trace.add_span(Span.new("node_a_operation") |> Span.finish())

      assert {:ok, %{last_export: last_export}} = File.export(trace, state)

      trace_export = read_json!(trace_file_path!(test_dir))
      evidence = read_json!(evidence_file_path!(test_dir))

      assert trace_export["source_node_ref"] == "node://aitrace_1@127.0.0.1/node-a"
      assert trace_export["node_evidence"]["node_role"] == "stacklab_probe"

      assert trace_export["node_order_evidence"] == %{
               "commit_hlc" => commit_hlc,
               "commit_lsn" => "16/B374D848",
               "source_node_ref" => "node://aitrace_1@127.0.0.1/node-a",
               "trace_id" => "trace_node_a"
             }

      assert hd(trace_export["spans"])["source_node_ref"] ==
               "node://aitrace_1@127.0.0.1/node-a"

      assert evidence["source_node_ref"] == "node://aitrace_1@127.0.0.1/node-a"
      assert evidence["node_evidence"]["node_instance_id"] == "node-instance-a"
      assert evidence["node_evidence"]["boot_generation"] == 3
      assert evidence["node_order_evidence"] == trace_export["node_order_evidence"]
      assert "source_node_ref" in evidence["proof_posture"]["requires"]

      assert last_export.source_node_ref == "node://aitrace_1@127.0.0.1/node-a"
      assert last_export.node_order_evidence.trace_id == "trace_node_a"
    end

    test "marks unanchored exports as not authoritative proof", %{test_dir: test_dir} do
      {:ok, state} = File.init(%{directory: test_dir})

      trace = Trace.new("trace_without_release_link")
      span = Span.new("operation") |> Span.finish()
      trace = Trace.add_span(trace, span)

      assert {:ok, %{last_export: last_export}} = File.export(trace, state)

      evidence = read_json!(evidence_file_path!(test_dir))

      assert evidence["trace_artifact_sha256"] == last_export.trace_artifact_sha256
      assert evidence["release_manifest_ref"] == nil
      assert evidence["evidence_owner_ref"] == nil
      assert evidence["proof_posture"]["authoritative_evidence?"] == false
      assert evidence["proof_posture"]["release_manifest_linked?"] == false
      assert evidence["proof_posture"]["evidence_owner_anchored?"] == false

      assert evidence["proof_posture"]["safe_action"] ==
               "release_manifest_ref_or_evidence_owner_ref_required_for_authoritative_proof"
    end

    test "writes valid JSON with span details", %{test_dir: test_dir} do
      {:ok, state} = File.init(%{directory: test_dir})

      trace = Trace.new("trace_123")

      span =
        Span.new("my_operation")
        |> Span.with_attributes(%{user_id: 42})
        |> Span.finish()

      trace = Trace.add_span(trace, span)

      {:ok, _state} = File.export(trace, state)

      data = read_json!(trace_file_path!(test_dir))

      span_data = hd(data["spans"])
      assert span_data["name"] == "my_operation"
      assert span_data["persistence_posture"]["raw_payload_persistence?"] == false
      assert span_data["attributes"]["user_id"] == 42
      assert is_integer(span_data["start_time"])
      assert is_integer(span_data["end_time"])
      assert is_binary(span_data["start_wall_time"])
      assert is_binary(span_data["end_wall_time"])
      assert is_integer(span_data["duration_microseconds"])
    end

    test "includes events in JSON output", %{test_dir: test_dir} do
      {:ok, state} = File.init(%{directory: test_dir})

      trace = Trace.new("trace_123")
      event = Event.new("cache_miss", %{key: "user_123"})

      span =
        Span.new("operation")
        |> Span.add_event(event)
        |> Span.finish()

      trace = Trace.add_span(trace, span)

      {:ok, _state} = File.export(trace, state)

      data = read_json!(trace_file_path!(test_dir))

      span_data = hd(data["spans"])
      assert is_list(span_data["events"])
      assert length(span_data["events"]) == 1

      event_data = hd(span_data["events"])
      assert event_data["name"] == "cache_miss"

      assert event_data["persistence_posture"]["capture_level_ref"] ==
               "capture-level://redacted-memory-ring"

      assert event_data["attributes"]["key"] == "user_123"
    end

    test "bounds raw exporter metadata and attributes", %{test_dir: test_dir} do
      {:ok, state} = File.init(%{directory: test_dir})

      trace =
        Trace.new("trace_bounds")
        |> Trace.with_metadata(%{
          safe_ref: "release:phase5",
          prompt_hash: "sha256:already-redacted",
          raw_prompt: "the original prompt must not be serialized",
          nested: %{provider_body: "raw provider body must not be serialized"},
          long_value: String.duplicate("x", 600)
        })

      event =
        Event.new("provider_call", %{
          safe_event: "provider.redacted",
          provider_response: "raw response must not be serialized"
        })

      span =
        Span.new("operation")
        |> Span.with_attributes(%{
          user_id: 42,
          raw_webhook_body: %{"secret" => "raw webhook body must not be serialized"}
        })
        |> Span.add_event(event)
        |> Span.finish()

      trace = Trace.add_span(trace, span)

      {:ok, _state} = File.export(trace, state)

      data = read_json!(trace_file_path!(test_dir))
      encoded = Jason.encode!(data)

      assert data["export_bounds"]["schema_version"] == "aitrace.export_bounds.v1"
      assert data["export_bounds"]["overflow_safe_action"] == "spill_to_artifact_ref"
      assert data["metadata"]["safe_ref"] == "release:phase5"
      assert data["metadata"]["prompt_hash"] == "sha256:already-redacted"
      refute Map.has_key?(data["metadata"], "raw_prompt")

      assert String.contains?(
               data["metadata"]["long_value"]["ref"],
               "aitrace://export-spillover/"
             )

      metadata_overflow = data["metadata"]["_aitrace_export_overflow"]
      assert metadata_overflow["overflow_safe_action"] == "spill_to_artifact_ref"
      assert metadata_overflow["count"] >= 1
      assert [%{"sha256" => sha256} | _] = metadata_overflow["refs"]
      assert byte_size(sha256) == 64

      span_attrs = hd(data["spans"])["attributes"]
      assert span_attrs["user_id"] == 42
      refute Map.has_key?(span_attrs, "raw_webhook_body")
      assert span_attrs["_aitrace_export_overflow"]["count"] == 1

      event_attrs = hd(hd(data["spans"])["events"])["attributes"]
      assert event_attrs["safe_event"] == "provider.redacted"
      refute Map.has_key?(event_attrs, "provider_response")
      assert event_attrs["_aitrace_export_overflow"]["count"] == 1

      refute String.contains?(encoded, "the original prompt must not be serialized")
      refute String.contains?(encoded, "raw provider body must not be serialized")
      refute String.contains?(encoded, "raw webhook body must not be serialized")
      refute String.contains?(encoded, "raw response must not be serialized")
    end

    test "filename includes trace_id and timestamp", %{test_dir: test_dir} do
      {:ok, state} = File.init(%{directory: test_dir})

      trace = Trace.new("my_trace")
      {:ok, _state} = File.export(trace, state)

      filename = Path.basename(trace_file_path!(test_dir))

      assert String.contains?(filename, "my_trace")
      assert String.contains?(filename, ".json")
    end
  end

  describe "shutdown/1" do
    test "returns :ok", %{test_dir: test_dir} do
      assert :ok = File.shutdown(%{directory: test_dir})
    end
  end

  defp exported_files(test_dir), do: Elixir.File.ls!(test_dir)

  defp trace_file_path!(test_dir) do
    test_dir
    |> exported_files()
    |> Enum.reject(&String.ends_with?(&1, ".evidence.json"))
    |> single_path!(test_dir)
  end

  defp evidence_file_path!(test_dir) do
    test_dir
    |> exported_files()
    |> Enum.filter(&String.ends_with?(&1, ".evidence.json"))
    |> single_path!(test_dir)
  end

  defp single_path!([filename], test_dir), do: Path.join(test_dir, filename)

  defp read_json!(path) do
    path
    |> Elixir.File.read!()
    |> Jason.decode!()
  end

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp replay_bundle(bundle_ref) do
    %{
      bundle_ref: bundle_ref,
      source_trace_ref: "trace://source",
      replay_trace_ref: "trace://replay",
      divergence_list_ref: "divergence://phase57",
      audit_ref: "audit://phase57",
      redaction_policy_ref: "redaction://default",
      release_manifest_ref: "release:replay-bundle"
    }
  end
end
