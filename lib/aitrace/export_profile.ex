defmodule AITrace.ExportProfile do
  @moduledoc """
  Explicit export configuration captured by a trace context.

  Standalone callers may rely on the boot default profile derived from
  application config. Governed callers should construct and pass a profile at
  the call site so export sinks are data on the trace context, not ambient VM
  state consulted at finish time.
  """

  @type exporter_config :: module() | {module(), keyword() | map()}

  @type t :: %__MODULE__{
          exporters: [exporter_config()],
          source: :explicit | :boot_default,
          metadata: map()
        }

  defstruct exporters: [], source: :explicit, metadata: %{}

  @governed_effect_profile_ref "aitrace.export_profile.governed_effect.v1"
  @governed_effect_included_evidence [
    "effect_lifecycle",
    "authority_decision",
    "dispatch",
    "receipt"
  ]
  @governed_effect_excluded_material [
    "raw_lower_payloads",
    "credentials",
    "prompts",
    "memory_bodies",
    "provider_bodies"
  ]

  @doc """
  Builds an explicit export profile.
  """
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      exporters: Map.get(attrs, :exporters, []),
      source: Map.get(attrs, :source, :explicit),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @doc """
  Captures the application-configured exporters as a boot default profile.
  """
  @spec boot_default() :: t()
  def boot_default do
    new(
      exporters: Application.get_env(:aitrace, :exporters) || [],
      source: :boot_default
    )
  end

  @doc """
  Builds the governed-effect export profile.
  """
  @spec governed_effect(keyword() | map()) :: t()
  def governed_effect(attrs \\ []) do
    attrs = normalize_attrs(attrs)
    metadata = Map.get(attrs, :metadata, %{})

    new(
      exporters: Map.get(attrs, :exporters, []),
      source: Map.get(attrs, :source, :explicit),
      metadata:
        Map.merge(metadata, %{
          profile_ref: @governed_effect_profile_ref,
          included_evidence: @governed_effect_included_evidence,
          excluded_material: @governed_effect_excluded_material,
          bounded_metadata?: true,
          replay_attachment?: true,
          redaction_policy_ref: "aitrace.governed_effect.redact_hash.v1"
        })
    )
  end

  defp normalize_attrs(attrs) when is_map(attrs), do: attrs

  defp normalize_attrs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      Map.new(attrs)
    else
      raise ArgumentError, "export profile attributes must be a keyword list or map"
    end
  end
end
