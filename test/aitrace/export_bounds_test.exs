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
          token: "raw token",
          safe_ref: "trace://safe"
        },
        surface: :span_attributes
      )

    assert bounded["safe_ref"] == "trace://safe"
    refute Map.has_key?(bounded, "memory_body")
    refute Map.has_key?(bounded, "budget_amount")
    refute Map.has_key?(bounded, "guard_violation_payload")
    refute Map.has_key?(bounded, "token")
    assert bounded["_aitrace_export_overflow"]["count"] == 4
  end

  test "unsupported spillover values become canonical safe refs" do
    bounded =
      ExportBounds.bound_map!(
        %{callback: fn -> :ok end},
        surface: :event_attributes
      )

    assert %{
             "ref" => "aitrace://export-spillover/" <> hash,
             "hash_algorithm" => "sha256",
             "reason" => "unsupported_value"
           } = bounded["callback"]

    assert byte_size(hash) == 64
  end

  test "capture profiles keep raw payload persistence disabled" do
    assert ExportBounds.capture_profile(:off) == %{
             capture_level_ref: "capture-level://off",
             retained?: false,
             raw_payload_persistence?: false,
             overflow_safe_action: "drop_without_mutating_provider_effect"
           }

    assert ExportBounds.capture_profile(:memory_ring).raw_payload_persistence? == false

    assert ExportBounds.capture_profile(:redacted_debug).capture_level_ref ==
             "capture-level://redacted-debug"
  end
end
