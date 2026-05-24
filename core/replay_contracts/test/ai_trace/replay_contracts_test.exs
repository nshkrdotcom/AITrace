defmodule AITrace.ReplayContractsTest do
  use ExUnit.Case, async: true

  alias AITrace.Integrations.AgentTurn
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
               context_packet_ref: "context-packet://a",
               context_packet_hash: "sha256:" <> String.duplicate("b", 64),
               route_decision_ref: "route-decision://a",
               model_invocation_ref: "model-invocation://a",
               model_receipt_ref: "model-receipt://a",
               decision_class: :diverged,
               cost_class: :replay,
               operator_action: "review",
               release_manifest_ref: "release://phase-c"
             })

    assert bundle.cost_class == :replay
    assert bundle.context_packet_ref == "context-packet://a"
    assert bundle.context_packet_hash == "sha256:" <> String.duplicate("b", 64)
    assert bundle.route_decision_ref == "route-decision://a"
    assert bundle.model_invocation_ref == "model-invocation://a"
    assert bundle.model_receipt_ref == "model-receipt://a"

    assert {:error, {:invalid_replay_field, :cost_class}} =
             bundle
             |> Map.from_struct()
             |> Map.put(:cost_class, :production)
             |> ReplayContracts.replay_bundle()

    assert {:error, {:invalid_replay_field, :context_packet_hash}} =
             bundle
             |> Map.from_struct()
             |> Map.put(:context_packet_hash, "not-sha")
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

  test "lineage replay events carry trace-level retention and emission expectations" do
    assert ReplayContracts.trace_levels() == [
             :core_lineage,
             :detailed_proof,
             :replay_minimum
           ]

    assert ReplayContracts.emission_modes() == [:inline, :async, :batched]

    expectations = [
      %{
        trace_level: :core_lineage,
        metadata_refs: %{
          retention_policy_ref: "retention://lineage/core/30d",
          ttl_seconds: 2_592_000,
          emission_mode: :async,
          emission_expectation_ref: "emission://lineage/core/async"
        }
      },
      %{
        trace_level: :detailed_proof,
        metadata_refs: %{
          retention_policy_ref: "retention://lineage/proof/90d",
          ttl_seconds: 7_776_000,
          emission_mode: :batched,
          batch_ref: "batch://lineage/proof/20260517",
          emission_expectation_ref: "emission://lineage/proof/batched"
        }
      },
      %{
        trace_level: :replay_minimum,
        metadata_refs: %{
          retention_policy_ref: "retention://lineage/replay-minimum/7d",
          ttl_seconds: 604_800,
          emission_mode: :inline,
          emission_expectation_ref: "emission://lineage/replay-minimum/inline"
        }
      }
    ]

    for expectation <- expectations do
      assert {:ok, event} =
               lineage_event_attrs()
               |> Map.merge(expectation)
               |> ReplayContracts.lineage_replay_event()

      assert event.trace_level == expectation.trace_level
      assert event.metadata_refs == expectation.metadata_refs
    end
  end

  test "lineage replay retention and emission expectations fail closed" do
    assert {:error, {:missing_replay_ref, :retention_policy_ref}} =
             lineage_event_attrs()
             |> put_metadata(:retention_policy_ref, "")
             |> ReplayContracts.lineage_replay_event()

    assert {:error, {:invalid_replay_field, :ttl_seconds}} =
             lineage_event_attrs()
             |> put_metadata(:ttl_seconds, 0)
             |> ReplayContracts.lineage_replay_event()

    assert {:error, {:invalid_replay_field, :emission_mode}} =
             lineage_event_attrs()
             |> put_metadata(:emission_mode, :fire_and_forget)
             |> ReplayContracts.lineage_replay_event()

    assert {:error, {:missing_replay_ref, :batch_ref}} =
             lineage_event_attrs()
             |> put_metadata(:emission_mode, :batched)
             |> ReplayContracts.lineage_replay_event()
  end

  test "trace level policies distinguish StackLab proof from production default" do
    assert ReplayContracts.trace_profiles() == [:production_default, :stacklab_proof]

    assert {:ok, production} = ReplayContracts.trace_level_policy(:production_default)
    assert production.default_trace_level == :core_lineage
    assert production.required_trace_level == :core_lineage
    assert production.allowed_trace_levels == [:core_lineage, :replay_minimum]
    assert production.required_event_kinds == []
    assert production.production_default?
    refute production.requires_detailed_proof?

    assert {:ok, proof} = ReplayContracts.trace_level_policy("stacklab_proof")
    assert proof.default_trace_level == :detailed_proof
    assert proof.required_trace_level == :detailed_proof
    assert proof.allowed_trace_levels == ReplayContracts.trace_levels()
    assert proof.requires_detailed_proof?
    refute proof.production_default?

    assert proof.required_event_kinds == [
             :operation_requested,
             :effect_requested,
             :effect_receipted,
             :receipt_reduced,
             :projection_updated
           ]

    assert {:error, {:invalid_replay_field, :trace_profile}} =
             ReplayContracts.trace_level_policy(:debug_dump)
  end

  test "agent evidence export requires ledger authority receipts redaction and hash refs" do
    assert {:ok, export} = ReplayContracts.agent_evidence_export(agent_export_attrs())

    assert export.export_ref == "agent-evidence-export://ledger-1/10-12"
    assert export.ledger_ref == "agent-ledger://run-1"
    assert export.runtime_receipt_refs == ["agent-runtime-receipt://run-1/tool-1"]
    assert export.export_profile == :redacted_replay
    assert export.payload_hash == "sha256:" <> String.duplicate("a", 64)
    assert export.ledger_seq_from == 10
    assert export.ledger_seq_to == 12
    assert export.event_count == 3

    assert {:error, {:missing_replay_ref, :redaction_manifest_ref}} =
             agent_export_attrs()
             |> Map.delete(:redaction_manifest_ref)
             |> ReplayContracts.agent_evidence_export()

    assert {:error, {:raw_replay_payload_forbidden, :raw_payload}} =
             agent_export_attrs()
             |> Map.put(:raw_payload, "raw lower response")
             |> ReplayContracts.agent_evidence_export()
  end

  test "agent evidence export fails closed for schema mismatch sequence gaps and authority claims" do
    assert {:error, {:schema_mismatch, "schema://wrong"}} =
             agent_export_attrs()
             |> Map.put(:schema_ref, "schema://wrong")
             |> ReplayContracts.agent_evidence_export()

    assert {:error, {:missing_replay_sequence, %{from_seq: 10, to_seq: 12, event_count: 2}}} =
             agent_export_attrs()
             |> Map.put(:event_count, 2)
             |> ReplayContracts.agent_evidence_export()

    assert {:error, {:missing_replay_ref, :durable_export_receipt_ref}} =
             agent_export_attrs()
             |> Map.put(:authoritative?, true)
             |> ReplayContracts.agent_evidence_export()
  end

  test "agent turn mapper exports bounded event evidence only" do
    assert {:ok, export} =
             AgentTurn.export_receipt(%{
               ledger_ref: "agent-ledger://run-1",
               authority_ref: "authority://run-1",
               trace_ref: "trace://run-1",
               runtime_receipt_refs: ["agent-runtime-receipt://run-1/tool-1"],
               redaction_manifest_ref: "redaction://agent/run-1",
               events: [
                 %{event_ref: "agent-event://run-1/10", event_kind: :conversation, seq: 10},
                 %{
                   event_ref: "agent-event://run-1/11",
                   event_kind: :execution,
                   seq: 11,
                   runtime_receipt_ref: "agent-runtime-receipt://run-1/tool-1"
                 },
                 %{event_ref: "agent-event://run-1/12", event_kind: :projection, seq: 12}
               ],
               exported_at: ~U[2026-05-21 00:00:00Z]
             })

    assert export.ledger_seq_from == 10
    assert export.ledger_seq_to == 12
    assert export.event_count == 3
    assert String.starts_with?(export.payload_hash, "sha256:")

    assert {:error, {:raw_agent_turn_event_payload_forbidden, :payload}} =
             AgentTurn.export_receipt(%{
               ledger_ref: "agent-ledger://run-1",
               authority_ref: "authority://run-1",
               trace_ref: "trace://run-1",
               runtime_receipt_refs: ["agent-runtime-receipt://run-1/tool-1"],
               redaction_manifest_ref: "redaction://agent/run-1",
               events: [
                 %{
                   event_ref: "agent-event://run-1/10",
                   event_kind: :conversation,
                   seq: 10,
                   payload: "raw prompt"
                 }
               ]
             })
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

  defp agent_export_attrs do
    %{
      export_ref: "agent-evidence-export://ledger-1/10-12",
      trace_ref: "trace://run-1",
      ledger_ref: "agent-ledger://run-1",
      runtime_receipt_refs: ["agent-runtime-receipt://run-1/tool-1"],
      authority_ref: "authority://run-1",
      export_profile: :redacted_replay,
      payload_hash: "sha256:" <> String.duplicate("a", 64),
      redaction_manifest_ref: "redaction://agent/run-1",
      exported_at: ~U[2026-05-21 00:00:00Z],
      schema_ref: "schema://aitrace/agent-evidence-export/v1",
      ledger_seq_from: 10,
      ledger_seq_to: 12,
      event_count: 3,
      authoritative?: false
    }
  end

  defp put_metadata(attrs, key, value) do
    Map.update!(attrs, :metadata_refs, &Map.put(&1, key, value))
  end
end
