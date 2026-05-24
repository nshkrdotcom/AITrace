defmodule AITrace.AIPlatformTest do
  use ExUnit.Case, async: true

  alias AITrace.AIPlatform

  test "memory spans use bounded names and reject raw memory bodies" do
    assert {:ok, span} =
             AIPlatform.memory_span(:write, %{
               tenant_ref: "tenant://a",
               authority_ref: "authority://a",
               installation_ref: "installation://a",
               idempotency_key: "idem-trace",
               trace_ref: "trace://a",
               memory_id: "memory://a",
               evidence_hash: "sha256:memory",
               redaction_policy_ref: "redaction-policy://memory"
             })

    assert span.name == "memory.write"
    assert span.attributes["memory_id"] == "memory://a"
    assert span.attributes["redaction_posture"] == "bounded_refs_only"

    assert {:error, {:raw_ai_platform_trace_payload_forbidden, :memory_body}} =
             AIPlatform.memory_span(:read, %{memory_body: "raw memory"})
  end

  test "budget spans and exhaustion events carry bounded attributes" do
    attrs = %{
      tenant_ref: "tenant://a",
      authority_ref: "authority://a",
      installation_ref: "installation://a",
      idempotency_key: "idem-budget-trace",
      trace_ref: "trace://a",
      decision_class: "deny_exhausted",
      requested_units: 10,
      granted_units: 0,
      residual_units: 0
    }

    assert {:ok, span} = AIPlatform.budget_enforcement_span(:preflight, attrs)
    assert span.name == "budget.enforce"
    assert span.attributes["locus"] == "preflight"

    assert {:ok, event} = AIPlatform.budget_exhaustion_event(:preflight, attrs)
    assert event.name == "budget.exhausted"
    assert event.attributes["decision_class"] == "deny_exhausted"

    assert {:ok, exhaust_event} = AIPlatform.budget_exhaust_event(:preflight, attrs)
    assert exhaust_event.name == "budget.exhaust"
  end

  test "cost spans and events carry bounded cost attributes" do
    attrs = %{
      cost_class: :production,
      amount_class: :redacted_below_floor,
      prompt_tokens: 10,
      completion_tokens: 5,
      cache_read_tokens: 2,
      cache_write_tokens: 1,
      provider_family: :codex_cli,
      model_ref: "model://codex/latest"
    }

    assert {:ok, span} = AIPlatform.cost_span(attrs)
    assert span.name == "cost.attribute"
    assert span.attributes["cost_class"] == "production"
    assert span.attributes["amount_class"] == "redacted_below_floor"

    assert {:ok, event} = AIPlatform.cost_attribution_event(attrs)
    assert event.name == "cost.attribute"
    assert event.attributes["provider_family"] == "codex_cli"

    assert {:error, {:raw_ai_platform_trace_payload_forbidden, :budget_amount}} =
             AIPlatform.cost_attribution_event(Map.put(attrs, :budget_amount, 10))
  end

  test "AI execution spans and events carry bounded trace classes" do
    assert {:ok, context_span} =
             AIPlatform.context_packet_compile_span(%{
               tenant_ref: "tenant://a",
               authority_ref: "authority://a",
               trace_ref: "trace://context",
               context_packet_ref: "context-packet://a",
               context_packet_hash: "sha256:" <> String.duplicate("a", 64)
             })

    assert context_span.name == "context_packet.compile"
    assert context_span.attributes["trace_class_ref"] == "aitrace.ai.context_packet_compile.v1"
    assert context_span.attributes["context_packet_ref"] == "context-packet://a"

    assert {:ok, route_span} =
             AIPlatform.route_decision_span(%{
               tenant_ref: "tenant://a",
               authority_ref: "authority://a",
               trace_ref: "trace://route",
               route_decision_ref: "route-decision://a",
               route_policy_ref: "route-policy://a"
             })

    assert route_span.name == "route.decide"
    assert route_span.attributes["trace_class_ref"] == "aitrace.ai.route_decision.v1"

    assert {:ok, model_span} =
             AIPlatform.model_call_span(%{
               tenant_ref: "tenant://a",
               authority_ref: "authority://a",
               trace_ref: "trace://model",
               model_invocation_ref: "model-invocation://a",
               model_receipt_ref: "model-receipt://a",
               model_profile_ref: "model-profile://fixture",
               provider_ref: "provider://fixture",
               endpoint_ref: "endpoint://fixture"
             })

    assert model_span.name == "model.call"
    assert model_span.attributes["trace_class_ref"] == "aitrace.ai.model_call.v1"

    assert {:ok, eval_event} =
             AIPlatform.eval_verdict_event(%{
               tenant_ref: "tenant://a",
               trace_ref: "trace://eval",
               eval_verdict_ref: "eval-verdict://a",
               eval_case_ref: "eval-case://a"
             })

    assert eval_event.name == "eval.verdict"
    assert eval_event.attributes["trace_class_ref"] == "aitrace.ai.eval_verdict.v1"

    assert {:ok, promotion_event} =
             AIPlatform.promotion_event(%{
               tenant_ref: "tenant://a",
               authority_ref: "authority://a",
               trace_ref: "trace://promotion",
               promotion_ref: "promotion://a",
               candidate_ref: "candidate://a"
             })

    assert promotion_event.name == "adaptive.promote"
    assert promotion_event.attributes["trace_class_ref"] == "aitrace.ai.promotion.v1"

    assert {:ok, rollback_event} =
             AIPlatform.rollback_event(%{
               tenant_ref: "tenant://a",
               authority_ref: "authority://a",
               trace_ref: "trace://rollback",
               rollback_ref: "rollback://a",
               rollback_target_ref: "candidate://previous"
             })

    assert rollback_event.name == "adaptive.rollback"
    assert rollback_event.attributes["trace_class_ref"] == "aitrace.ai.rollback.v1"
  end

  test "AI execution helpers reject raw payloads and missing refs" do
    assert {:error, {:missing_ai_platform_trace_ref, :context_packet_hash}} =
             AIPlatform.context_packet_compile_span(%{
               tenant_ref: "tenant://a",
               trace_ref: "trace://context",
               context_packet_ref: "context-packet://a"
             })

    assert {:error, {:raw_ai_platform_trace_payload_forbidden, :provider_payload}} =
             AIPlatform.model_call_span(%{
               tenant_ref: "tenant://a",
               trace_ref: "trace://model",
               model_invocation_ref: "model-invocation://a",
               model_profile_ref: "model-profile://fixture",
               provider_ref: "provider://fixture",
               endpoint_ref: "endpoint://fixture",
               provider_payload: "raw provider payload"
             })

    assert {:error, {:raw_ai_platform_trace_payload_forbidden, :eval_payload}} =
             AIPlatform.eval_verdict_event(%{
               tenant_ref: "tenant://a",
               trace_ref: "trace://eval",
               eval_verdict_ref: "eval-verdict://a",
               eval_payload: "raw eval payload"
             })
  end

  test "prompt and guard spans carry bounded refs and reject raw guard material" do
    assert {:ok, prompt_span} =
             AIPlatform.prompt_resolution_span(%{
               tenant_ref: "tenant://a",
               authority_ref: "authority://a",
               installation_ref: "installation://a",
               idempotency_key: "idem-prompt-trace",
               trace_ref: "trace://prompt",
               prompt_id: "prompt://a",
               revision: 1,
               decision_class: "resolved"
             })

    assert prompt_span.name == "prompt.resolve"
    assert prompt_span.attributes["prompt_id"] == "prompt://a"

    assert {:ok, guard_span} =
             AIPlatform.guard_evaluation_span(%{
               tenant_ref: "tenant://a",
               authority_ref: "authority://a",
               installation_ref: "installation://a",
               idempotency_key: "idem-guard-trace",
               trace_ref: "trace://guard",
               payload_kind: "input_prompt",
               detector_chain_ref: "guard-chain://a",
               decision_class: "block",
               redaction_posture: "block"
             })

    assert guard_span.name == "guard.evaluate"
    assert guard_span.attributes["detector_chain_ref"] == "guard-chain://a"

    assert {:ok, event} =
             AIPlatform.guard_violation_event(%{
               trace_ref: "trace://guard",
               violation_id: "guard-violation://a",
               detector_ref: "detector://a",
               severity: "block",
               bounded_redacted_excerpt: "bounded"
             })

    assert event.name == "guard.violate"
    assert event.attributes["bounded_redacted_excerpt"] == "bounded"

    assert {:error, {:raw_ai_platform_trace_payload_forbidden, :guard_violation_payload}} =
             AIPlatform.guard_evaluation_span(%{guard_violation_payload: "raw"})
  end
end
