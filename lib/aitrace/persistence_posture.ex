defmodule AITrace.PersistencePosture do
  @moduledoc """
  Capture and persistence posture for AITrace evidence.

  This module describes trace storage behavior only. It never authorizes a
  provider effect and never makes trace evidence authoritative audit truth.
  """

  @profiles %{
    mickey_mouse: %{
      persistence_profile_ref: "persistence-profile://mickey-mouse",
      persistence_tier_ref: "persistence-tier://memory-ephemeral",
      capture_level_ref: "capture-level://redacted-memory-ring",
      store_set_ref: "store-set://aitrace/memory-ring",
      retention_policy_ref: "retention://lost-on-process-exit",
      debug_tap_ref: "debug-tap://noop",
      durable?: false,
      retained?: true
    },
    off: %{
      persistence_profile_ref: "persistence-profile://trace-off",
      persistence_tier_ref: "persistence-tier://off",
      capture_level_ref: "capture-level://off",
      store_set_ref: "store-set://off",
      retention_policy_ref: "retention://disabled",
      debug_tap_ref: "debug-tap://noop",
      durable?: false,
      retained?: false
    },
    memory_debug: %{
      persistence_profile_ref: "persistence-profile://memory-debug",
      persistence_tier_ref: "persistence-tier://memory-ephemeral",
      capture_level_ref: "capture-level://redacted-debug",
      store_set_ref: "store-set://aitrace/redacted-memory-ring",
      retention_policy_ref: "retention://lost-on-process-exit",
      debug_tap_ref: "debug-tap://memory-ring",
      durable?: false,
      retained?: true
    },
    durable_redacted: %{
      persistence_profile_ref: "persistence-profile://aitrace-durable-redacted",
      persistence_tier_ref: "persistence-tier://durable",
      capture_level_ref: "capture-level://redacted-summary",
      store_set_ref: "store-set://aitrace/durable-redacted",
      retention_policy_ref: "retention://operator-configured",
      debug_tap_ref: "debug-tap://noop",
      durable?: true,
      retained?: true
    }
  }

  @surfaces %{
    trace: "component://aitrace/trace",
    span: "component://aitrace/span",
    event: "component://aitrace/event",
    authority_trace: "component://aitrace/authority-trace",
    export: "component://aitrace/export",
    replay: "component://aitrace/replay",
    proof_trace: "component://aitrace/proof-trace"
  }

  @profile_lookup %{
    "mickey_mouse" => :mickey_mouse,
    "off" => :off,
    "memory_debug" => :memory_debug,
    "durable_redacted" => :durable_redacted
  }

  @type surface :: :trace | :span | :event | :authority_trace | :export | :replay | :proof_trace

  @type t :: %{
          surface_ref: String.t(),
          persistence_profile_ref: String.t(),
          persistence_tier_ref: String.t(),
          capture_level_ref: String.t(),
          store_set_ref: String.t(),
          retention_policy_ref: String.t(),
          debug_tap_ref: String.t(),
          persistence_receipt_ref: String.t(),
          durable?: boolean(),
          retained?: boolean(),
          raw_payload_persistence?: false
        }

  @spec memory_ring(surface()) :: t()
  def memory_ring(surface), do: resolve(surface, %{})

  @spec off(surface()) :: t()
  def off(surface), do: resolve(surface, %{persistence_profile: :off})

  @spec durable(surface()) :: t()
  def durable(surface), do: resolve(surface, %{persistence_profile: :durable_redacted})

  @spec resolve(surface(), map() | keyword() | nil) :: t()
  def resolve(surface, attrs \\ %{}) do
    attrs = normalize_attrs(attrs)

    case Map.get(attrs, :persistence_posture) do
      posture when is_map(posture) ->
        posture
        |> normalize_attrs()
        |> Map.merge(base(surface, profile_from_attrs(posture)), fn _key, value, _base ->
          value
        end)
        |> ensure_surface(surface)

      _other ->
        base(surface, profile_from_attrs(attrs))
    end
  end

  @spec retained?(t()) :: boolean()
  def retained?(posture), do: Map.get(posture, :retained?) == true

  @spec debug_tap_failed(map()) :: map()
  def debug_tap_failed(posture) when is_map(posture) do
    posture
    |> Map.put(:debug_tap_result, :failed_non_mutating)
    |> Map.put(:debug_sidecar_mutated_state?, false)
  end

  @spec export_attributes(t()) :: map()
  def export_attributes(posture) when is_map(posture) do
    %{
      "persistence_profile_ref" => posture.persistence_profile_ref,
      "persistence_tier_ref" => posture.persistence_tier_ref,
      "capture_level_ref" => posture.capture_level_ref,
      "store_set_ref" => posture.store_set_ref,
      "retention_policy_ref" => posture.retention_policy_ref,
      "debug_tap_ref" => posture.debug_tap_ref,
      "persistence_receipt_ref" => posture.persistence_receipt_ref,
      "raw_payload_persistence?" => false,
      "retained?" => posture.retained?,
      "durable?" => posture.durable?
    }
  end

  defp base(surface, profile) do
    profile_values = Map.fetch!(@profiles, profile)
    surface_ref = Map.fetch!(@surfaces, surface)

    profile_values
    |> Map.put(:surface_ref, surface_ref)
    |> Map.put(:persistence_receipt_ref, receipt_ref(surface, profile))
    |> Map.put(:raw_payload_persistence?, false)
  end

  defp ensure_surface(posture, surface) do
    posture
    |> Map.put_new(:surface_ref, Map.fetch!(@surfaces, surface))
    |> Map.put_new(:persistence_receipt_ref, receipt_ref(surface, :mickey_mouse))
    |> Map.put(:raw_payload_persistence?, false)
  end

  defp profile_from_attrs(attrs) do
    attrs = normalize_attrs(attrs)

    attrs
    |> Map.get(:persistence_profile, Map.get(attrs, :persistence_profile_ref, :mickey_mouse))
    |> normalize_profile()
  end

  defp normalize_profile(profile) when is_atom(profile) and is_map_key(@profiles, profile),
    do: profile

  defp normalize_profile(profile) when is_binary(profile) do
    cond do
      Map.has_key?(@profile_lookup, profile) -> Map.fetch!(@profile_lookup, profile)
      String.contains?(profile, "trace-off") -> :off
      String.contains?(profile, "memory-debug") -> :memory_debug
      String.contains?(profile, "durable") -> :durable_redacted
      true -> :mickey_mouse
    end
  end

  defp normalize_profile(_profile), do: :mickey_mouse

  defp normalize_attrs(nil), do: %{}
  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {string_key(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp normalize_attrs(_attrs), do: %{}

  defp string_key("persistence_profile"), do: :persistence_profile
  defp string_key("persistence_profile_ref"), do: :persistence_profile_ref
  defp string_key("persistence_posture"), do: :persistence_posture
  defp string_key("retained?"), do: :retained?
  defp string_key("durable?"), do: :durable?
  defp string_key(key), do: key

  defp receipt_ref(surface, profile), do: "persistence-receipt://aitrace/#{surface}/#{profile}"
end
