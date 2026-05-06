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
end
