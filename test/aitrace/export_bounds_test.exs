defmodule AITrace.ExportBoundsTest do
  use ExUnit.Case, async: true

  alias AITrace.ExportBounds

  test "memory body and budget amount classes are explicit redaction classes" do
    assert ExportBounds.memory_body_class().safe_action == "hash_ref_or_redacted_excerpt_only"

    assert ExportBounds.budget_amount_class().safe_action ==
             "redact_amounts_above_export_threshold"
  end

  test "memory bodies and budget amounts spill instead of exporting inline" do
    bounded =
      ExportBounds.bound_map!(
        %{
          memory_body: "raw memory",
          budget_amount: 500_000,
          safe_ref: "trace://safe"
        },
        surface: :span_attributes
      )

    assert bounded["safe_ref"] == "trace://safe"
    refute Map.has_key?(bounded, "memory_body")
    refute Map.has_key?(bounded, "budget_amount")
    assert bounded["_aitrace_export_overflow"]["count"] == 2
  end
end
