defmodule AITrace.PersistencePostureTest do
  use ExUnit.Case, async: true

  alias AITrace.PersistencePosture

  test "memory ring posture is redacted and non-durable" do
    posture = PersistencePosture.memory_ring(:trace)

    assert posture.persistence_profile_ref == "persistence-profile://mickey-mouse"
    assert posture.capture_level_ref == "capture-level://redacted-memory-ring"
    assert posture.retained? == true
    assert posture.durable? == false
    assert posture.raw_payload_persistence? == false
  end

  test "capture off disables retention without changing provider effect semantics" do
    posture = PersistencePosture.off(:span)

    assert posture.capture_level_ref == "capture-level://off"
    assert posture.retained? == false
    assert posture.store_set_ref == "store-set://off"
    assert posture.raw_payload_persistence? == false
  end

  test "debug tap failure is recorded as non-mutating evidence" do
    posture =
      :event
      |> PersistencePosture.memory_ring()
      |> PersistencePosture.debug_tap_failed()

    assert posture.debug_tap_result == :failed_non_mutating
    assert posture.debug_sidecar_mutated_state? == false
    assert posture.persistence_profile_ref == "persistence-profile://mickey-mouse"
  end
end
