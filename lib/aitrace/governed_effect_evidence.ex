defmodule AITrace.GovernedEffectEvidence do
  @moduledoc """
  Redaction-safe governed-effect evidence trace builder.

  The evidence record keeps provider payloads and credential material out of
  trace attributes. Sensitive fields are preserved as GAOP tombstones so replay
  can prove a field existed without exporting the raw value.
  """

  alias AITrace.{ExportBounds, Span, Trace}

  @required_refs [:trace_ref, :effect_ref, :command_ref, :authority_ref, :receipt_ref]

  @type t :: %__MODULE__{
          trace_ref: String.t(),
          effect_ref: String.t(),
          command_ref: String.t(),
          authority_ref: String.t(),
          receipt_ref: String.t(),
          transitions: [map()],
          authority_decision: map(),
          lower_execution: map(),
          receipt_reduction: map(),
          redaction_posture: :standard,
          export_profile: :governed_effect
        }

  @enforce_keys @required_refs
  defstruct @required_refs ++
              [
                transitions: [],
                authority_decision: %{},
                lower_execution: %{},
                receipt_reduction: %{},
                redaction_posture: :standard,
                export_profile: :governed_effect
              ]

  @doc """
  Builds a governed-effect evidence record.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, refs} <- required_refs(attrs),
         {:ok, transitions} <- transitions(attrs),
         {:ok, authority_decision} <- section(attrs, :authority_decision),
         {:ok, lower_execution} <- section(attrs, :lower_execution),
         {:ok, receipt_reduction} <- section(attrs, :receipt_reduction) do
      {:ok,
       struct!(
         __MODULE__,
         Map.merge(refs, %{
           transitions: transitions,
           authority_decision: authority_decision,
           lower_execution: lower_execution,
           receipt_reduction: receipt_reduction,
           redaction_posture: :standard,
           export_profile: :governed_effect
         })
       )}
    end
  end

  @doc """
  Builds a governed-effect evidence record and raises on invalid input.
  """
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, evidence} ->
        evidence

      {:error, reason} ->
        raise ArgumentError, "invalid governed effect evidence: #{inspect(reason)}"
    end
  end

  @doc """
  Converts governed-effect evidence into an AITrace trace.
  """
  @spec to_trace(t()) :: Trace.t()
  def to_trace(%__MODULE__{} = evidence) do
    trace =
      evidence.trace_ref
      |> Trace.new()
      |> Trace.with_metadata(trace_metadata(evidence))

    {trace, parent_span_id} =
      evidence.transitions
      |> Enum.reduce({trace, nil}, fn transition, {trace, parent_span_id} ->
        span =
          build_span(
            "governed_effect.transition",
            parent_span_id,
            evidence,
            "effect_lifecycle_transition",
            transition
          )

        {Trace.add_span(trace, span), span.span_id}
      end)

    {trace, parent_span_id} =
      add_section_span(
        trace,
        parent_span_id,
        "governed_effect.authority_decision",
        evidence,
        "authority_decision",
        evidence.authority_decision
      )

    {trace, parent_span_id} =
      add_section_span(
        trace,
        parent_span_id,
        "governed_effect.lower_execution",
        evidence,
        "lower_execution",
        evidence.lower_execution
      )

    {trace, _parent_span_id} =
      add_section_span(
        trace,
        parent_span_id,
        "governed_effect.receipt_reduction",
        evidence,
        "receipt_reduction",
        evidence.receipt_reduction
      )

    trace
  end

  defp add_section_span(trace, parent_span_id, name, evidence, record_type, attrs) do
    span = build_span(name, parent_span_id, evidence, record_type, attrs)
    {Trace.add_span(trace, span), span.span_id}
  end

  defp build_span(name, parent_span_id, evidence, record_type, attrs) do
    name
    |> new_span(parent_span_id)
    |> Span.with_attributes(
      evidence
      |> common_attrs(record_type)
      |> Map.merge(ExportBounds.tombstone_map!(attrs))
    )
    |> Span.finish()
  end

  defp new_span(name, nil), do: Span.new(name)
  defp new_span(name, parent_span_id), do: Span.new(name, parent_span_id)

  defp trace_metadata(evidence) do
    %{
      effect_ref: evidence.effect_ref,
      command_ref: evidence.command_ref,
      authority_ref: evidence.authority_ref,
      receipt_ref: evidence.receipt_ref,
      redaction_posture: Atom.to_string(evidence.redaction_posture),
      export_profile: Atom.to_string(evidence.export_profile)
    }
  end

  defp common_attrs(evidence, record_type) do
    %{
      "evidence_record_type" => record_type,
      "effect_ref" => evidence.effect_ref,
      "command_ref" => evidence.command_ref,
      "authority_ref" => evidence.authority_ref,
      "receipt_ref" => evidence.receipt_ref,
      "redaction_posture" => Atom.to_string(evidence.redaction_posture),
      "export_profile" => Atom.to_string(evidence.export_profile)
    }
  end

  defp required_refs(attrs) do
    refs =
      @required_refs
      |> Enum.map(fn key -> {key, Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))} end)
      |> Map.new()

    missing =
      refs
      |> Enum.reject(fn {_key, value} -> is_binary(value) and String.trim(value) != "" end)
      |> Enum.map(fn {key, _value} -> key end)

    if missing == [] do
      {:ok, refs}
    else
      {:error, {:missing_required_refs, missing}}
    end
  end

  defp transitions(attrs) do
    case Map.get(attrs, :transitions, Map.get(attrs, "transitions", [])) do
      transitions when is_list(transitions) ->
        {:ok, Enum.map(transitions, &normalize_section!/1)}

      other ->
        {:error, {:invalid_transitions, other}}
    end
  end

  defp section(attrs, key) do
    case Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), %{})) do
      section when is_map(section) -> {:ok, normalize_section!(section)}
      other -> {:error, {:invalid_section, key, other}}
    end
  end

  defp normalize_section!(section) when is_map(section) do
    section
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp normalize_attrs(attrs) when is_map(attrs), do: attrs

  defp normalize_attrs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      Map.new(attrs)
    else
      raise ArgumentError, "governed effect evidence attributes must be a keyword list or map"
    end
  end
end
