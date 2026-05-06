defmodule AITrace.ExportBoundsTest do
  use ExUnit.Case, async: true

  alias AITrace.ExportBounds

  test "memory body and budget amount classes are explicit redaction classes" do
    assert ExportBounds.memory_body_class().safe_action == "hash_ref_or_redacted_excerpt_only"

    assert ExportBounds.budget_amount_class().safe_action ==
             "redact_amounts_above_export_threshold"

    assert ExportBounds.cost_amount_floor_class().safe_action ==
             "redact_provider_amounts_below_floor_to_class"

    assert ExportBounds.cost_amount_ceiling_class().safe_action ==
             "hash_provider_amounts_above_ceiling_to_ref"

    assert ExportBounds.prompt_body_class().safe_action ==
             "always_redact_prompt_body_to_hash_ref"

    assert ExportBounds.guard_violation_excerpt_class().safe_action ==
             "bounded_excerpt_only_never_raw_payload"
  end

  test "memory bodies and budget amounts spill instead of exporting inline" do
    bounded =
      ExportBounds.bound_map!(
        %{
          memory_body: "raw memory",
          budget_amount: 500_000,
          guard_violation_payload: "raw guard",
          safe_ref: "trace://safe"
        },
        surface: :span_attributes
      )

    assert bounded["safe_ref"] == "trace://safe"
    refute Map.has_key?(bounded, "memory_body")
    refute Map.has_key?(bounded, "budget_amount")
    refute Map.has_key?(bounded, "guard_violation_payload")
    assert bounded["_aitrace_export_overflow"]["count"] == 3
  end
end
