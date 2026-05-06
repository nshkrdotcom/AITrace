defmodule AITrace.AIPlatform do
  @moduledoc """
  AI Platform span and event constructors with redaction-safe attributes.
  """

  alias AITrace.{Event, ExportBounds, Span}

  @memory_operations [:write, :read, :evict]
  @budget_loci [:preflight, :append, :stream, :runtime_admission, :reconciliation]
  @replay_events [:replay_executed, :eval_case, :drift_signal]
  @cost_classes [:production, :replay, :eval, :simulation, :infrastructure]
  @amount_classes [
    :production_native,
    :redacted_below_floor,
    :redacted_above_ceiling,
    :bounded_excerpt
  ]
  @raw_payload_keys [
    :body,
    :raw_body,
    :memory_body,
    :raw_memory_body,
    :prompt_body,
    :guard_payload,
    :guard_violation_body,
    :guard_violation_payload,
    :provider_payload,
    :model_output,
    :replay_divergence_excerpt,
    :raw_guard,
    :secret,
    :token,
    :budget_amount,
    "body",
    "raw_body",
    "memory_body",
    "raw_memory_body",
    "prompt_body",
    "guard_payload",
    "guard_violation_body",
    "guard_violation_payload",
    "provider_payload",
    "model_output",
    "replay_divergence_excerpt",
    "raw_guard",
    "secret",
    "token",
    "budget_amount"
  ]

  @spec memory_span(atom(), map()) :: {:ok, Span.t()} | {:error, term()}
  def memory_span(operation, attrs) when operation in @memory_operations and is_map(attrs) do
    with {:ok, bounded} <- bounded_attrs(attrs, %{operation: Atom.to_string(operation)}) do
      {:ok, Span.new("memory." <> Atom.to_string(operation)) |> Span.with_attributes(bounded)}
    end
  end

  def memory_span(operation, _attrs), do: {:error, {:invalid_memory_span_operation, operation}}

  @spec budget_enforcement_span(atom(), map()) :: {:ok, Span.t()} | {:error, term()}
  def budget_enforcement_span(locus, attrs) when locus in @budget_loci and is_map(attrs) do
    with {:ok, bounded} <- bounded_attrs(attrs, %{locus: Atom.to_string(locus)}) do
      {:ok, Span.new("budget.enforce") |> Span.with_attributes(bounded)}
    end
  end

  def budget_enforcement_span(locus, _attrs), do: {:error, {:invalid_budget_locus, locus}}

  @spec budget_exhaustion_event(atom(), map()) :: {:ok, Event.t()} | {:error, term()}
  def budget_exhaustion_event(locus, attrs) when locus in @budget_loci and is_map(attrs) do
    with {:ok, bounded} <- bounded_attrs(attrs, %{locus: Atom.to_string(locus)}) do
      {:ok, Event.new("budget.exhausted", bounded)}
    end
  end

  def budget_exhaustion_event(locus, _attrs), do: {:error, {:invalid_budget_locus, locus}}

  @spec budget_exhaust_event(atom(), map()) :: {:ok, Event.t()} | {:error, term()}
  def budget_exhaust_event(locus, attrs) when locus in @budget_loci and is_map(attrs) do
    with {:ok, bounded} <- bounded_attrs(attrs, %{locus: Atom.to_string(locus)}) do
      {:ok, Event.new("budget.exhaust", bounded)}
    end
  end

  def budget_exhaust_event(locus, _attrs), do: {:error, {:invalid_budget_locus, locus}}

  @spec prompt_resolution_span(map()) :: {:ok, Span.t()} | {:error, term()}
  def prompt_resolution_span(attrs) when is_map(attrs) do
    with {:ok, bounded} <- bounded_attrs(attrs, %{}) do
      {:ok, Span.new("prompt.resolve") |> Span.with_attributes(bounded)}
    end
  end

  @spec guard_evaluation_span(map()) :: {:ok, Span.t()} | {:error, term()}
  def guard_evaluation_span(attrs) when is_map(attrs) do
    with {:ok, bounded} <- bounded_attrs(attrs, %{}) do
      {:ok, Span.new("guard.evaluate") |> Span.with_attributes(bounded)}
    end
  end

  @spec guard_violation_event(map()) :: {:ok, Event.t()} | {:error, term()}
  def guard_violation_event(attrs) when is_map(attrs) do
    with {:ok, bounded} <- bounded_attrs(attrs, %{}) do
      {:ok, Event.new("guard.violate", bounded)}
    end
  end

  @spec replay_span(map()) :: {:ok, Span.t()} | {:error, term()}
  def replay_span(attrs) when is_map(attrs) do
    with {:ok, bounded} <- bounded_attrs(attrs, %{cost_class: "replay"}) do
      {:ok, Span.new("replay.execute") |> Span.with_attributes(bounded)}
    end
  end

  @spec eval_span(map()) :: {:ok, Span.t()} | {:error, term()}
  def eval_span(attrs) when is_map(attrs) do
    with {:ok, bounded} <- bounded_attrs(attrs, %{cost_class: "eval"}) do
      {:ok, Span.new("eval.run") |> Span.with_attributes(bounded)}
    end
  end

  @spec cost_span(map()) :: {:ok, Span.t()} | {:error, term()}
  def cost_span(attrs) when is_map(attrs) do
    with {:ok, additions} <- cost_additions(attrs),
         {:ok, bounded} <- bounded_attrs(attrs, additions) do
      {:ok, Span.new("cost.attribute") |> Span.with_attributes(bounded)}
    end
  end

  @spec cost_attribution_event(map()) :: {:ok, Event.t()} | {:error, term()}
  def cost_attribution_event(attrs) when is_map(attrs) do
    with {:ok, additions} <- cost_additions(attrs),
         {:ok, bounded} <- bounded_attrs(attrs, additions) do
      {:ok, Event.new("cost.attribute", bounded)}
    end
  end

  @spec replay_event(atom(), map()) :: {:ok, Event.t()} | {:error, term()}
  def replay_event(event, attrs) when event in @replay_events and is_map(attrs) do
    with {:ok, bounded} <- bounded_attrs(attrs, %{event_class: Atom.to_string(event)}) do
      {:ok, Event.new("replay." <> Atom.to_string(event), bounded)}
    end
  end

  def replay_event(event, _attrs), do: {:error, {:invalid_replay_event, event}}

  defp bounded_attrs(attrs, additions) do
    with :ok <- reject_raw_payload(attrs) do
      {:ok,
       attrs
       |> Map.merge(additions)
       |> Map.put_new(:redaction_posture, "bounded_refs_only")
       |> ExportBounds.bound_map!(surface: :span_attributes)}
    end
  end

  defp cost_additions(attrs) do
    with {:ok, cost_class} <- enum_value(attrs, :cost_class, @cost_classes),
         {:ok, amount_class} <- enum_value(attrs, :amount_class, @amount_classes) do
      {:ok,
       %{
         cost_class: Atom.to_string(cost_class),
         amount_class: Atom.to_string(amount_class)
       }}
    end
  end

  defp enum_value(attrs, field, allowed) do
    case Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field)) do
      value when is_atom(value) ->
        if value in allowed do
          {:ok, value}
        else
          {:error, {:unknown_ai_platform_trace_enum, field}}
        end

      value when is_binary(value) ->
        case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
          nil -> {:error, {:unknown_ai_platform_trace_enum, field}}
          found -> {:ok, found}
        end

      _value ->
        {:error, {:unknown_ai_platform_trace_enum, field}}
    end
  end

  defp reject_raw_payload(attrs) do
    case Enum.find(@raw_payload_keys, &Map.has_key?(attrs, &1)) do
      nil -> :ok
      key -> {:error, {:raw_ai_platform_trace_payload_forbidden, key}}
    end
  end
end
