defmodule AITrace.GovernedEffectEvidenceTest do
  use ExUnit.Case, async: true

  alias AITrace.{ExportBounds, ExportProfile, GovernedEffectEvidence, Span, Trace}

  test "governed effect export profile defines included and excluded evidence classes" do
    profile = ExportProfile.governed_effect()

    assert profile.metadata.profile_ref == "aitrace.export_profile.governed_effect.v1"

    assert profile.metadata.included_evidence == [
             "effect_lifecycle",
             "authority_decision",
             "dispatch",
             "receipt"
           ]

    assert "raw_lower_payloads" in profile.metadata.excluded_material
    assert "credentials" in profile.metadata.excluded_material
    assert "memory_bodies" in profile.metadata.excluded_material
    assert profile.metadata.replay_attachment? == true
  end

  test "tombstone map preserves redacted fields without raw material" do
    redacted =
      ExportBounds.tombstone_map!(%{
        safe_ref: "effect://tenant-1/effects/1",
        raw_payload: "lower execution payload",
        prompt_body: "prompt text",
        nested: %{credential_material: "secret credential"}
      })

    assert redacted["safe_ref"] == "effect://tenant-1/effects/1"
    assert String.starts_with?(redacted["raw_payload"], "[REDACTED: sha256:")
    assert String.ends_with?(redacted["raw_payload"], "]")
    assert String.starts_with?(redacted["prompt_body"], "[REDACTED: sha256:")
    assert String.starts_with?(redacted["nested"]["credential_material"], "[REDACTED: sha256:")

    encoded = inspect(redacted)
    refute String.contains?(encoded, "lower execution payload")
    refute String.contains?(encoded, "prompt text")
    refute String.contains?(encoded, "secret credential")
  end

  test "governed effect evidence exports lifecycle authority lower execution and receipt spans" do
    evidence = GovernedEffectEvidence.new!(valid_attrs())
    trace = GovernedEffectEvidence.to_trace(evidence)

    assert %Trace{} = trace
    assert trace.trace_id == "trace:tenant-1:effects:1"
    assert trace.metadata.effect_ref == "effect://tenant-1/effects/1"
    assert trace.metadata.command_ref == "command://tenant-1/commands/1"
    assert trace.metadata.authority_ref == "authority://tenant-1/decisions/1"
    assert trace.metadata.receipt_ref == "receipt://tenant-1/receipts/1"
    assert trace.metadata.export_profile == "governed_effect"

    assert [
             %Span{name: "governed_effect.transition"} = accepted_span,
             %Span{name: "governed_effect.transition"} = dispatched_span,
             %Span{name: "governed_effect.authority_decision"} = authority_span,
             %Span{name: "governed_effect.lower_execution"} = lower_span,
             %Span{name: "governed_effect.receipt_reduction"} = receipt_span
           ] = trace.spans

    assert accepted_span.attributes["evidence_record_type"] == "effect_lifecycle_transition"
    assert dispatched_span.parent_span_id == accepted_span.span_id
    assert authority_span.parent_span_id == dispatched_span.span_id
    assert lower_span.parent_span_id == authority_span.span_id
    assert receipt_span.parent_span_id == lower_span.span_id

    assert authority_span.attributes["authority_ref"] == "authority://tenant-1/decisions/1"
    assert lower_span.attributes["lower_execution_ref"] == "lower://tenant-1/runs/1"
    assert receipt_span.attributes["receipt_ref"] == "receipt://tenant-1/receipts/1"

    assert String.starts_with?(lower_span.attributes["raw_payload"], "[REDACTED: sha256:")
    assert String.starts_with?(lower_span.attributes["credential_material"], "[REDACTED: sha256:")
    assert String.starts_with?(authority_span.attributes["prompt_body"], "[REDACTED: sha256:")
    assert String.starts_with?(receipt_span.attributes["memory_body"], "[REDACTED: sha256:")

    encoded = inspect(trace)
    refute String.contains?(encoded, "raw lower payload")
    refute String.contains?(encoded, "secret lease material")
    refute String.contains?(encoded, "raw prompt")
    refute String.contains?(encoded, "raw memory")
  end

  defp valid_attrs do
    %{
      trace_ref: "trace:tenant-1:effects:1",
      effect_ref: "effect://tenant-1/effects/1",
      command_ref: "command://tenant-1/commands/1",
      authority_ref: "authority://tenant-1/decisions/1",
      receipt_ref: "receipt://tenant-1/receipts/1",
      transitions: [
        %{
          transition_ref: "transition://tenant-1/effects/1/accepted",
          from_state: "requested",
          to_state: "accepted"
        },
        %{
          transition_ref: "transition://tenant-1/effects/1/dispatched",
          from_state: "accepted",
          to_state: "dispatched"
        }
      ],
      authority_decision: %{
        authority_ref: "authority://tenant-1/decisions/1",
        decision: "admitted",
        prompt_body: "raw prompt"
      },
      lower_execution: %{
        lower_execution_ref: "lower://tenant-1/runs/1",
        dispatch_ref: "dispatch://tenant-1/runs/1",
        raw_payload: "raw lower payload",
        credential_material: "secret lease material"
      },
      receipt_reduction: %{
        receipt_ref: "receipt://tenant-1/receipts/1",
        disposition: "completed",
        memory_body: "raw memory"
      }
    }
  end
end
