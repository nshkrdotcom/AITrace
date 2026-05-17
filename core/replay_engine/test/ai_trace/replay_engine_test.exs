defmodule AITrace.ReplayEngineTest do
  use ExUnit.Case, async: true

  alias AITrace.{ReplayEngine, Span, Trace}

  test "clean replay reconstructs deterministic replay spans without side effects" do
    trace = source_trace()

    assert {:ok, result} =
             ReplayEngine.replay(request_attrs(),
               trace_store: %{"trace-source-a" => trace},
               authorized_tenants: ["tenant://a"]
             )

    assert result.side_effects_invoked? == false
    assert result.bundle.decision_class == :clean
    assert result.bundle.cost_class == :replay
    assert result.divergences == []
    assert Enum.map(result.replay_trace.spans, & &1.span_id) == ["replay-span://span-1"]
  end

  test "missing, unauthorized, cross-tenant, and live-effect replay fail closed" do
    assert {:error, :missing_source_trace} =
             ReplayEngine.replay(request_attrs(), trace_store: %{})

    assert {:error, :unauthorized_replay} =
             ReplayEngine.replay(request_attrs(),
               trace_store: %{"trace-source-a" => source_trace()},
               authorized_tenants: ["tenant://other"]
             )

    assert {:error, :cross_tenant_replay_forbidden} =
             ReplayEngine.replay(request_attrs(),
               trace_store: %{
                 "trace-source-a" =>
                   Trace.with_metadata(source_trace(), %{tenant_ref: "tenant://other"})
               }
             )

    assert {:error, :replay_live_provider_effect_forbidden} =
             ReplayEngine.replay(request_attrs(),
               trace_store: %{"trace-source-a" => source_trace()},
               live_provider_effect?: true
             )
  end

  test "variant replay accumulates bounded divergence markers deterministically" do
    attrs =
      request_attrs()
      |> Map.put(:replay_mode, :guard_variant)
      |> Map.put(:variant_overrides, %{guard_chain_ref: "guard-chain://candidate"})

    assert {:ok, result} =
             ReplayEngine.replay(attrs, trace_store: %{"trace-source-a" => source_trace()})

    assert result.bundle.decision_class == :diverged
    assert [%{phase: :guard_decision, redacted_excerpt_class: excerpt_class}] = result.divergences
    assert String.contains?(excerpt_class, "aitrace.redaction.replay.variant_override.v1")
  end

  test "lineage replay compares emit order and causal order without projection drift" do
    events = [
      lineage_event("lineage://command", :command_recorded, 10,
        root_event?: true,
        projection_visible?: false
      ),
      lineage_event("lineage://evidence-b", :effect_receipted, 30,
        predecessor_event_refs: ["lineage://command"],
        projection_key: "projection://document-review/evidence",
        projection_order_key: "document-review:030"
      ),
      lineage_event("lineage://evidence-a", :effect_receipted, 20,
        predecessor_event_refs: ["lineage://command"],
        projection_key: "projection://document-review/evidence",
        projection_order_key: "document-review:020"
      ),
      lineage_event("lineage://projection", :projection_updated, 40,
        predecessor_event_refs: ["lineage://evidence-a", "lineage://evidence-b"],
        projection_key: "projection://document-review/status",
        merge_semantics: :last_write_by_causal_order,
        projection_order_key: "document-review:040"
      )
    ]

    assert {:ok, report} =
             ReplayEngine.replay_lineage_events(events,
               required_event_kinds: [:command_recorded, :effect_receipted, :projection_updated]
             )

    assert report.emit_order_event_refs == [
             "lineage://command",
             "lineage://evidence-b",
             "lineage://evidence-a",
             "lineage://projection"
           ]

    assert report.causal_order_event_refs == [
             "lineage://command",
             "lineage://evidence-a",
             "lineage://evidence-b",
             "lineage://projection"
           ]

    assert report.order_diverged? == true
    assert report.projection_diverged? == false
    assert report.divergences == []

    assert report.projection_outputs.emit_order == report.projection_outputs.causal_order

    assert report.projection_outputs.causal_order["projection://document-review/evidence"] == %{
             merge_semantics: :set_union,
             event_refs: ["lineage://evidence-a", "lineage://evidence-b"]
           }
  end

  test "lineage replay reports projection-visible divergence" do
    events = [
      lineage_event("lineage://root", :command_recorded, 10,
        root_event?: true,
        projection_visible?: false
      ),
      lineage_event("lineage://state-late", :projection_updated, 30,
        predecessor_event_refs: ["lineage://root"],
        projection_key: "projection://document-review/state",
        merge_semantics: :state_transition,
        projection_order_key: "document-review:030"
      ),
      lineage_event("lineage://state-early", :projection_updated, 20,
        predecessor_event_refs: ["lineage://root"],
        projection_key: "projection://document-review/state",
        merge_semantics: :state_transition,
        projection_order_key: "document-review:020"
      )
    ]

    assert {:ok, report} = ReplayEngine.replay_lineage_events(events)

    assert report.order_diverged? == true
    assert report.projection_diverged? == true
    assert [%{projection_key: "projection://document-review/state"}] = report.divergences
  end

  test "lineage replay reports trace-level retention and emission expectations" do
    events = [
      lineage_event("lineage://retention/core", :command_recorded, 10,
        root_event?: true,
        projection_visible?: false,
        trace_level: :core_lineage,
        metadata_refs: %{
          retention_policy_ref: "retention://lineage/core/30d",
          ttl_seconds: 2_592_000,
          emission_mode: :async,
          emission_expectation_ref: "emission://lineage/core/async"
        }
      ),
      lineage_event("lineage://retention/proof", :effect_receipted, 20,
        predecessor_event_refs: ["lineage://retention/core"],
        projection_key: "projection://document-review/evidence",
        trace_level: :detailed_proof,
        metadata_refs: %{
          retention_policy_ref: "retention://lineage/proof/90d",
          ttl_seconds: 7_776_000,
          emission_mode: :batched,
          batch_ref: "batch://lineage/proof/20260517",
          emission_expectation_ref: "emission://lineage/proof/batched"
        }
      ),
      lineage_event("lineage://retention/replay", :replay_exported, 30,
        predecessor_event_refs: ["lineage://retention/proof"],
        projection_visible?: false,
        trace_level: :replay_minimum,
        metadata_refs: %{
          retention_policy_ref: "retention://lineage/replay-minimum/7d",
          ttl_seconds: 604_800,
          emission_mode: :inline,
          emission_expectation_ref: "emission://lineage/replay-minimum/inline"
        }
      )
    ]

    assert {:ok, report} = ReplayEngine.replay_lineage_events(events)

    assert report.trace_level_expectations[:core_lineage] == %{
             event_refs: ["lineage://retention/core"],
             retention_policy_refs: ["retention://lineage/core/30d"],
             ttl_seconds: [2_592_000],
             emission_modes: [:async],
             batch_refs: [],
             emission_expectation_refs: ["emission://lineage/core/async"]
           }

    assert report.trace_level_expectations[:detailed_proof] == %{
             event_refs: ["lineage://retention/proof"],
             retention_policy_refs: ["retention://lineage/proof/90d"],
             ttl_seconds: [7_776_000],
             emission_modes: [:batched],
             batch_refs: ["batch://lineage/proof/20260517"],
             emission_expectation_refs: ["emission://lineage/proof/batched"]
           }

    assert report.trace_level_expectations[:replay_minimum] == %{
             event_refs: ["lineage://retention/replay"],
             retention_policy_refs: ["retention://lineage/replay-minimum/7d"],
             ttl_seconds: [604_800],
             emission_modes: [:inline],
             batch_refs: [],
             emission_expectation_refs: ["emission://lineage/replay-minimum/inline"]
           }
  end

  test "trace profile allows production default to stay on core lineage" do
    events = [
      lineage_event("lineage://production/command", :command_recorded, 10,
        root_event?: true,
        projection_visible?: false,
        trace_level: :core_lineage
      ),
      lineage_event("lineage://production/effect", :effect_receipted, 20,
        predecessor_event_refs: ["lineage://production/command"],
        projection_key: "projection://production/effects",
        trace_level: :core_lineage
      ),
      lineage_event("lineage://production/projection", :projection_updated, 30,
        predecessor_event_refs: ["lineage://production/effect"],
        projection_key: "projection://production/readback",
        trace_level: :core_lineage
      ),
      lineage_event("lineage://production/replay", :replay_exported, 40,
        predecessor_event_refs: ["lineage://production/projection"],
        projection_visible?: false,
        trace_level: :replay_minimum
      )
    ]

    assert {:ok, report} =
             ReplayEngine.replay_lineage_events(events, trace_profile: :production_default)

    assert report.trace_level_policy == %{
             profile: :production_default,
             default_trace_level: :core_lineage,
             required_trace_level: :core_lineage,
             allowed_trace_levels: [:core_lineage, :replay_minimum],
             required_event_kinds: [],
             requires_detailed_proof?: false,
             production_default?: true
           }

    refute Map.has_key?(report.trace_level_expectations, :detailed_proof)

    detailed_event =
      lineage_event("lineage://production/detailed", :effect_receipted, 50,
        predecessor_event_refs: ["lineage://production/replay"],
        projection_key: "projection://production/effects",
        trace_level: :detailed_proof
      )

    assert {:error, {:disallowed_trace_level, :production_default, :detailed_proof}} =
             ReplayEngine.replay_lineage_events(events ++ [detailed_event],
               trace_profile: :production_default
             )
  end

  test "trace profile requires detailed proof for StackLab proof-critical events" do
    events = [
      lineage_event("lineage://stacklab/command", :command_recorded, 10,
        root_event?: true,
        projection_visible?: false,
        trace_level: :core_lineage
      ),
      lineage_event("lineage://stacklab/operation", :operation_requested, 20,
        predecessor_event_refs: ["lineage://stacklab/command"],
        projection_key: "projection://stacklab/proof/operations",
        trace_level: :detailed_proof
      ),
      lineage_event("lineage://stacklab/effect-request", :effect_requested, 30,
        predecessor_event_refs: ["lineage://stacklab/operation"],
        projection_key: "projection://stacklab/proof/effects",
        trace_level: :detailed_proof
      ),
      lineage_event("lineage://stacklab/effect-receipt", :effect_receipted, 40,
        predecessor_event_refs: ["lineage://stacklab/effect-request"],
        projection_key: "projection://stacklab/proof/effects",
        trace_level: :detailed_proof
      ),
      lineage_event("lineage://stacklab/receipt", :receipt_reduced, 50,
        predecessor_event_refs: ["lineage://stacklab/effect-receipt"],
        projection_key: "projection://stacklab/proof/receipts",
        trace_level: :detailed_proof
      ),
      lineage_event("lineage://stacklab/projection", :projection_updated, 60,
        predecessor_event_refs: ["lineage://stacklab/receipt"],
        projection_key: "projection://stacklab/proof/readback",
        merge_semantics: :last_write_by_causal_order,
        trace_level: :detailed_proof
      ),
      lineage_event("lineage://stacklab/replay", :replay_exported, 70,
        predecessor_event_refs: ["lineage://stacklab/projection"],
        projection_visible?: false,
        trace_level: :replay_minimum
      )
    ]

    assert {:ok, report} =
             ReplayEngine.replay_lineage_events(events, trace_profile: :stacklab_proof)

    assert report.trace_level_policy.profile == :stacklab_proof
    assert report.trace_level_policy.requires_detailed_proof?

    assert report.trace_level_policy.required_event_kinds == [
             :operation_requested,
             :effect_requested,
             :effect_receipted,
             :receipt_reduced,
             :projection_updated
           ]

    assert report.trace_level_expectations[:detailed_proof].event_refs == [
             "lineage://stacklab/effect-receipt",
             "lineage://stacklab/effect-request",
             "lineage://stacklab/operation",
             "lineage://stacklab/projection",
             "lineage://stacklab/receipt"
           ]

    missing_receipt_detail =
      Enum.map(events, fn
        %{event_kind: :receipt_reduced} = event -> %{event | trace_level: :core_lineage}
        event -> event
      end)

    assert {:error,
            {:missing_trace_level_event_kinds, :stacklab_proof, :detailed_proof,
             [:receipt_reduced]}} =
             ReplayEngine.replay_lineage_events(missing_receipt_detail,
               trace_profile: :stacklab_proof
             )
  end

  test "lineage replay reconstructs an Extravaganza product execution-record DAG" do
    events = [
      lineage_event("lineage://extravaganza/projection-updated", :projection_updated, 90,
        predecessor_event_refs: [
          "lineage://extravaganza/receipt-reduced",
          "lineage://extravaganza/evidence-attached"
        ],
        projection_key: "projection://extravaganza/run/run-17",
        projection_order_key: "extravaganza:090",
        merge_semantics: :last_write_by_causal_order,
        trace_level: :core_lineage
      ),
      lineage_event("lineage://extravaganza/effect-requested", :effect_requested, 60,
        predecessor_event_refs: ["lineage://extravaganza/credential-lease"],
        projection_key: "projection://extravaganza/provider-facts",
        projection_order_key: "extravaganza:060",
        merge_semantics: :map_merge_by_key,
        trace_level: :core_lineage,
        metadata_refs: %{
          projection_entries: %{
            "provider" => "linear",
            "operation" => "linear.comments.create"
          }
        }
      ),
      lineage_event("lineage://extravaganza/command", :command_recorded, 10,
        root_event?: true,
        projection_visible?: false,
        trace_level: :core_lineage
      ),
      lineage_event("lineage://extravaganza/workflow", :workflow_started, 20,
        predecessor_event_refs: ["lineage://extravaganza/command"],
        projection_visible?: false,
        trace_level: :core_lineage
      ),
      lineage_event("lineage://extravaganza/operation-requested", :operation_requested, 30,
        predecessor_event_refs: ["lineage://extravaganza/workflow"],
        projection_key: "projection://extravaganza/operations",
        projection_order_key: "extravaganza:030",
        trace_level: :core_lineage
      ),
      lineage_event("lineage://extravaganza/manifest", :jido_manifest_resolved, 40,
        predecessor_event_refs: ["lineage://extravaganza/operation-requested"],
        projection_key: "projection://extravaganza/provider-facts",
        projection_order_key: "extravaganza:040",
        merge_semantics: :map_merge_by_key,
        trace_level: :core_lineage,
        metadata_refs: %{
          projection_entries: %{
            "connector_manifest_ref" => "manifest://linear/comments/v1"
          }
        }
      ),
      lineage_event("lineage://extravaganza/credential-lease", :credential_lease_materialized, 50,
        predecessor_event_refs: ["lineage://extravaganza/manifest"],
        projection_visible?: false,
        trace_level: :core_lineage
      ),
      lineage_event("lineage://extravaganza/effect-receipted", :effect_receipted, 70,
        predecessor_event_refs: ["lineage://extravaganza/effect-requested"],
        projection_key: "projection://extravaganza/provider-facts",
        projection_order_key: "extravaganza:070",
        merge_semantics: :map_merge_by_key,
        trace_level: :core_lineage,
        metadata_refs: %{
          projection_entries: %{
            "provider_object_ref" => "linear-comment://comment-1"
          }
        }
      ),
      lineage_event("lineage://extravaganza/receipt-reduced", :receipt_reduced, 80,
        predecessor_event_refs: ["lineage://extravaganza/effect-receipted"],
        projection_key: "projection://extravaganza/receipts",
        projection_order_key: "extravaganza:080",
        trace_level: :core_lineage
      ),
      lineage_event("lineage://extravaganza/evidence-attached", :evidence_attached, 85,
        predecessor_event_refs: ["lineage://extravaganza/receipt-reduced"],
        projection_key: "projection://extravaganza/evidence",
        projection_order_key: "extravaganza:085",
        trace_level: :core_lineage
      ),
      lineage_event("lineage://extravaganza/replay-exported", :replay_exported, 100,
        predecessor_event_refs: ["lineage://extravaganza/projection-updated"],
        projection_visible?: false,
        trace_level: :replay_minimum
      )
    ]

    assert {:ok, report} =
             ReplayEngine.replay_lineage_events(events,
               required_event_kinds: [
                 :command_recorded,
                 :workflow_started,
                 :operation_requested,
                 :jido_manifest_resolved,
                 :credential_lease_materialized,
                 :effect_requested,
                 :effect_receipted,
                 :receipt_reduced,
                 :evidence_attached,
                 :projection_updated,
                 :replay_exported
               ]
             )

    assert report.replay_complete? == true
    assert report.order_diverged? == true
    assert report.projection_diverged? == false

    assert report.causal_order_event_refs == [
             "lineage://extravaganza/command",
             "lineage://extravaganza/workflow",
             "lineage://extravaganza/operation-requested",
             "lineage://extravaganza/manifest",
             "lineage://extravaganza/credential-lease",
             "lineage://extravaganza/effect-requested",
             "lineage://extravaganza/effect-receipted",
             "lineage://extravaganza/receipt-reduced",
             "lineage://extravaganza/evidence-attached",
             "lineage://extravaganza/projection-updated",
             "lineage://extravaganza/replay-exported"
           ]

    assert report.projection_outputs.causal_order["projection://extravaganza/provider-facts"] ==
             %{
               merge_semantics: :map_merge_by_key,
               entries: %{
                 "connector_manifest_ref" => "manifest://linear/comments/v1",
                 "operation" => "linear.comments.create",
                 "provider" => "linear",
                 "provider_object_ref" => "linear-comment://comment-1"
               },
               event_refs: [
                 "lineage://extravaganza/effect-receipted",
                 "lineage://extravaganza/effect-requested",
                 "lineage://extravaganza/manifest"
               ]
             }

    assert report.projection_outputs.causal_order["projection://extravaganza/run/run-17"] ==
             %{
               merge_semantics: :last_write_by_causal_order,
               causal_order: 90,
               projection_order_key: "extravaganza:090",
               event_ref: "lineage://extravaganza/projection-updated"
             }
  end

  test "lineage replay reconstructs a neutral toy document review execution-record DAG" do
    events = [
      lineage_event("lineage://toy/review-evidence", :effect_receipted, 60,
        predecessor_event_refs: ["lineage://toy/review-runtime"],
        projection_key: "projection://toy-document-review/operations",
        projection_order_key: "toy:060"
      ),
      lineage_event("lineage://toy/semantic-intent", :semantic_intent, 10,
        root_event?: true,
        projection_visible?: false
      ),
      lineage_event("lineage://toy/semantic-normalized", :semantic_normalized, 20,
        predecessor_event_refs: ["lineage://toy/semantic-intent"],
        projection_visible?: false
      ),
      lineage_event("lineage://toy/command", :command_recorded, 30,
        predecessor_event_refs: ["lineage://toy/semantic-normalized"],
        projection_visible?: false
      ),
      lineage_event("lineage://toy/authority", :authority_compiled, 35,
        predecessor_event_refs: ["lineage://toy/command"],
        projection_visible?: false
      ),
      lineage_event("lineage://toy/review-runtime-request", :operation_requested, 40,
        predecessor_event_refs: ["lineage://toy/authority"],
        projection_key: "projection://toy-document-review/operations",
        projection_order_key: "toy:040"
      ),
      lineage_event("lineage://toy/review-extract-tool", :effect_receipted, 45,
        predecessor_event_refs: ["lineage://toy/review-runtime-request"],
        projection_key: "projection://toy-document-review/operations",
        projection_order_key: "toy:045"
      ),
      lineage_event("lineage://toy/review-runtime", :effect_receipted, 50,
        predecessor_event_refs: ["lineage://toy/review-runtime-request"],
        projection_key: "projection://toy-document-review/operations",
        projection_order_key: "toy:050"
      ),
      lineage_event("lineage://toy/review-opened", :review_opened, 70,
        predecessor_event_refs: ["lineage://toy/review-evidence"],
        projection_key: "projection://toy-document-review/review",
        projection_order_key: "toy:070",
        merge_semantics: :state_transition
      ),
      lineage_event("lineage://toy/review-projection", :projection_updated, 80,
        predecessor_event_refs: ["lineage://toy/review-opened"],
        projection_key: "projection://toy-document-review/status",
        projection_order_key: "toy:080",
        merge_semantics: :last_write_by_causal_order
      ),
      lineage_event("lineage://toy/replay-exported", :replay_exported, 90,
        predecessor_event_refs: ["lineage://toy/review-projection"],
        projection_visible?: false,
        trace_level: :replay_minimum
      )
    ]

    assert {:ok, report} =
             ReplayEngine.replay_lineage_events(events,
               required_event_kinds: [
                 :semantic_intent,
                 :semantic_normalized,
                 :command_recorded,
                 :authority_compiled,
                 :operation_requested,
                 :effect_receipted,
                 :review_opened,
                 :projection_updated,
                 :replay_exported
               ]
             )

    assert report.replay_complete? == true
    assert report.order_diverged? == true
    assert report.projection_diverged? == false

    assert report.causal_order_event_refs == [
             "lineage://toy/semantic-intent",
             "lineage://toy/semantic-normalized",
             "lineage://toy/command",
             "lineage://toy/authority",
             "lineage://toy/review-runtime-request",
             "lineage://toy/review-extract-tool",
             "lineage://toy/review-runtime",
             "lineage://toy/review-evidence",
             "lineage://toy/review-opened",
             "lineage://toy/review-projection",
             "lineage://toy/replay-exported"
           ]

    assert report.projection_outputs.causal_order["projection://toy-document-review/operations"] ==
             %{
               merge_semantics: :set_union,
               event_refs: [
                 "lineage://toy/review-evidence",
                 "lineage://toy/review-extract-tool",
                 "lineage://toy/review-runtime",
                 "lineage://toy/review-runtime-request"
               ]
             }

    assert report.projection_outputs.causal_order["projection://toy-document-review/status"] ==
             %{
               merge_semantics: :last_write_by_causal_order,
               causal_order: 80,
               projection_order_key: "toy:080",
               event_ref: "lineage://toy/review-projection"
             }
  end

  test "lineage replay fails closed for missing predecessors and required event kinds" do
    assert {:error, {:missing_predecessor_events, missing}} =
             ReplayEngine.replay_lineage_events([
               lineage_event("lineage://receipt", :effect_receipted, 20,
                 predecessor_event_refs: ["lineage://missing"],
                 projection_key: "projection://document-review/evidence"
               )
             ])

    assert missing == [
             %{event_ref: "lineage://receipt", missing_predecessor_ref: "lineage://missing"}
           ]

    assert {:error, {:missing_required_event_kinds, [:projection_updated]}} =
             ReplayEngine.replay_lineage_events(
               [
                 lineage_event("lineage://command", :command_recorded, 10,
                   root_event?: true,
                   projection_visible?: false
                 )
               ],
               required_event_kinds: [:command_recorded, :projection_updated]
             )
  end

  defp source_trace do
    span =
      %Span{
        span_id: "span-1",
        span_id_source: %{kind: "fixture"},
        parent_span_id: nil,
        parent_span_id_source: nil,
        name: "provider.response",
        start_time: 1,
        start_wall_time: ~U[2026-05-05 00:00:00Z],
        end_time: 2,
        end_wall_time: ~U[2026-05-05 00:00:01Z],
        clock_domain: %{kind: "fixture"},
        attributes: %{guard_decision_ref: "guard://source"},
        events: [],
        status: :ok
      }

    "trace-source-a"
    |> Trace.new()
    |> Trace.add_span(span)
    |> Trace.with_metadata(%{tenant_ref: "tenant://a", replay_addressable?: true})
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

  defp lineage_event(event_ref, event_kind, causal_order, attrs) do
    attrs = Map.new(attrs)
    projection_visible? = Map.get(attrs, :projection_visible?, true)
    projection_key = Map.get(attrs, :projection_key)

    %{
      event_ref: event_ref,
      trace_ref: "trace://document-review",
      event_kind: event_kind,
      occurred_at: causal_order,
      predecessor_event_refs: Map.get(attrs, :predecessor_event_refs, []),
      root_event?: Map.get(attrs, :root_event?, false),
      projection_key: projection_key,
      projection_visible?: projection_visible?,
      projection_order_key: Map.get(attrs, :projection_order_key, event_ref),
      causal_order: causal_order,
      merge_semantics: Map.get(attrs, :merge_semantics, :set_union),
      trace_level: Map.get(attrs, :trace_level, :detailed_proof),
      metadata_refs: Map.get(attrs, :metadata_refs, %{})
    }
  end
end
