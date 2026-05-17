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
