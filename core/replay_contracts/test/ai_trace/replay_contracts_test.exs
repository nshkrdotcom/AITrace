defmodule AITrace.ReplayContractsTest do
  use ExUnit.Case, async: true

  alias AITrace.ReplayContracts

  test "replay requests require bounded modes and side-effect policies" do
    assert {:ok, request} = ReplayContracts.replay_request(request_attrs())
    assert request.replay_mode == :exact
    assert request.side_effect_policy == :suppress

    assert {:error, {:invalid_replay_field, :replay_mode}} =
             request_attrs()
             |> Map.put(:replay_mode, :free_form)
             |> ReplayContracts.replay_request()

    assert {:error, {:invalid_replay_field, :side_effect_policy}} =
             request_attrs()
             |> Map.put(:side_effect_policy, :live_provider)
             |> ReplayContracts.replay_request()
  end

  test "replay requests reject missing source trace, cross tenant source, and raw payloads" do
    assert {:error, {:missing_replay_ref, :source_trace_id}} =
             request_attrs()
             |> Map.delete(:source_trace_id)
             |> ReplayContracts.replay_request()

    assert {:error, :cross_tenant_replay_forbidden} =
             request_attrs()
             |> Map.put(:source_tenant_ref, "tenant://other")
             |> ReplayContracts.replay_request()

    assert {:error, {:raw_replay_payload_forbidden, :provider_payload}} =
             request_attrs()
             |> Map.put(:provider_payload, "raw provider data")
             |> ReplayContracts.replay_request()
  end

  test "replay divergences and bundles are ref-only and replay-cost only" do
    assert {:ok, divergence} = ReplayContracts.replay_divergence(divergence_attrs())
    assert divergence.phase == :guard_decision

    assert {:ok, bundle} =
             ReplayContracts.replay_bundle(%{
               tenant_ref: "tenant://a",
               authority_ref: "authority://a",
               installation_ref: "installation://a",
               idempotency_key: "idem-replay",
               trace_ref: "trace://replay",
               source_trace_ref: "trace://source",
               replay_trace_ref: "trace://replay/1",
               divergence_refs: ["replay-divergence://1"],
               decision_class: :diverged,
               cost_class: :replay,
               operator_action: "review",
               release_manifest_ref: "release://phase-c"
             })

    assert bundle.cost_class == :replay

    assert {:error, {:invalid_replay_field, :cost_class}} =
             bundle
             |> Map.from_struct()
             |> Map.put(:cost_class, :production)
             |> ReplayContracts.replay_bundle()
  end

  test "lineage replay events are ref-only and bounded by trace level" do
    assert {:ok, event} = ReplayContracts.lineage_replay_event(lineage_event_attrs())

    assert event.event_kind == :effect_receipted
    assert event.trace_level == :detailed_proof
    assert event.predecessor_event_refs == ["lineage://source"]
    assert event.projection_visible? == true

    assert {:error, {:invalid_replay_field, :trace_level}} =
             lineage_event_attrs()
             |> Map.put(:trace_level, :verbose_dump)
             |> ReplayContracts.lineage_replay_event()

    assert {:error, {:missing_replay_ref, :projection_key}} =
             lineage_event_attrs()
             |> Map.put(:projection_visible?, true)
             |> Map.delete(:projection_key)
             |> ReplayContracts.lineage_replay_event()

    assert {:error, {:raw_replay_payload_forbidden, :payload}} =
             lineage_event_attrs()
             |> Map.put(:payload, "raw lower response")
             |> ReplayContracts.lineage_replay_event()
  end

  defp request_attrs do
    %{
      tenant_ref: "tenant://a",
      authority_ref: "authority://a",
      installation_ref: "installation://a",
      idempotency_key: "idem-replay",
      trace_ref: "trace://replay",
      source_trace_id: "trace-source-a",
      replay_mode: :exact,
      variant_overrides: %{},
      side_effect_policy: :suppress,
      divergence_thresholds: %{},
      persistence_ref: "persistence://memory/default",
      release_manifest_ref: "release://phase-c"
    }
  end

  defp divergence_attrs do
    %{
      divergence_ref: "replay-divergence://1",
      phase: :guard_decision,
      severity: :regress,
      redacted_excerpt_class: "aitrace.redaction.replay_divergence.v1",
      remediation_class: :operator_decision,
      source_span_ref: "span://source/1",
      replay_span_ref: "span://replay/1"
    }
  end

  defp lineage_event_attrs do
    %{
      event_ref: "lineage://receipt",
      trace_ref: "trace://lineage",
      event_kind: :effect_receipted,
      occurred_at: 3,
      predecessor_event_refs: ["lineage://source"],
      projection_key: "projection://document-review/evidence",
      projection_visible?: true,
      projection_order_key: "document-review:020",
      causal_order: 20,
      merge_semantics: :set_union,
      trace_level: :detailed_proof,
      metadata_refs: %{receipt_ref: "receipt://effect"}
    }
  end
end
