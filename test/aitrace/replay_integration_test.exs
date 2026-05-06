defmodule AITrace.ReplayIntegrationTest do
  use ExUnit.Case, async: true

  alias AITrace.{AIPlatform, ExportBounds, Trace}
  alias AITrace.Exporter.File, as: FileExporter
  alias AITrace.Trace.ReplayBundle

  test "production traces are replay-addressable by default" do
    trace = Trace.new("trace-replay-addressable")

    assert Trace.replay_addressable?(trace)
    refute trace |> Trace.mark_replay_addressable(false) |> Trace.replay_addressable?()
  end

  test "replay spans and events reject raw payload-bearing attributes" do
    assert {:ok, span} =
             AIPlatform.replay_span(%{
               tenant_ref: "tenant://a",
               trace_ref: "trace://a",
               replay_bundle_ref: "replay-bundle://a"
             })

    assert span.attributes["cost_class"] == "replay"

    assert {:error, {:raw_ai_platform_trace_payload_forbidden, :model_output}} =
             AIPlatform.replay_span(%{
               tenant_ref: "tenant://a",
               trace_ref: "trace://a",
               model_output: "raw output"
             })
  end

  test "replay export bounds declare bounded divergence excerpt class" do
    class = ExportBounds.replay_divergence_excerpt_class()

    assert class.class_ref == "aitrace.redaction.replay_divergence_excerpt.v1"
    assert "model_output" in class.blocked_field_fragments
  end

  test "file exporter writes replay bundles away from production trace files" do
    directory = Path.join(System.tmp_dir!(), "aitrace-replay-export-#{System.unique_integer()}")

    {:ok, state} =
      FileExporter.init(directory: directory, release_manifest_ref: "release://phase-c")

    assert {:ok, bundle} =
             ReplayBundle.new(%{
               bundle_ref: "replay-bundle://phase-c/1",
               source_trace_ref: "trace://source",
               replay_trace_ref: "trace://replay",
               divergence_list_ref: "divergence-list://phase-c/1",
               audit_ref: "audit://phase-c/1",
               redaction_policy_ref: "redaction://replay",
               release_manifest_ref: "release://phase-c"
             })

    assert {:ok, receipt} = FileExporter.export_replay_bundle(bundle, state)

    assert receipt.source_trace_ref == "trace://source"
    assert String.ends_with?(receipt.replay_bundle_artifact_ref, ".json")

    assert File.exists?(
             Path.join([directory, "replay_bundles", receipt.replay_bundle_artifact_ref])
           )

    File.rm_rf!(directory)
  end
end
