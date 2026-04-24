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

    test "creates directory if it doesn't exist", %{test_dir: test_dir} do
      dir = Path.join(test_dir, "new_dir")
      refute :filelib.is_dir(String.to_charlist(dir))

      {:ok, _state} = File.init(%{directory: dir})

      assert :filelib.is_dir(String.to_charlist(dir))
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
      assert is_binary(data["created_at_wall_time"])
      assert data["clock_domain"]["monotonic_unit"] == "microsecond"
      assert is_list(data["spans"])
      assert length(data["spans"]) == 1
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

      assert evidence["proof_posture"]["authoritative_evidence?"] == true
      assert evidence["proof_posture"]["release_manifest_linked?"] == true
      assert evidence["proof_posture"]["evidence_owner_anchored?"] == true
      assert evidence["proof_posture"]["safe_action"] == "cite_evidence_receipt"

      assert last_export.trace_artifact_sha256 == sha256(trace_json)
      assert last_export.release_manifest_ref == "release:phase5-v7-m5"
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
      assert data["metadata"]["long_value"]["ref"] =~ "aitrace://export-spillover/"

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

      refute encoded =~ "the original prompt must not be serialized"
      refute encoded =~ "raw provider body must not be serialized"
      refute encoded =~ "raw webhook body must not be serialized"
      refute encoded =~ "raw response must not be serialized"
    end

    test "filename includes trace_id and timestamp", %{test_dir: test_dir} do
      {:ok, state} = File.init(%{directory: test_dir})

      trace = Trace.new("my_trace")
      {:ok, _state} = File.export(trace, state)

      filename = Path.basename(trace_file_path!(test_dir))

      assert filename =~ "my_trace"
      assert filename =~ ".json"
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
end
