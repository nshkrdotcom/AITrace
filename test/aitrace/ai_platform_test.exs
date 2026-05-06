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
