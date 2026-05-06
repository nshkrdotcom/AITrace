defmodule AITrace.AIPlatform do
  @moduledoc """
  AI Platform span and event constructors with redaction-safe attributes.
  """

  alias AITrace.{Event, ExportBounds, Span}

  @memory_operations [:write, :read, :evict]
  @budget_loci [:preflight, :append, :stream, :runtime_admission, :reconciliation]
  @raw_payload_keys [
    :body,
    :raw_body,
    :memory_body,
    :raw_memory_body,
    :prompt_body,
    :provider_payload,
    :secret,
    :token,
    :budget_amount,
    "body",
    "raw_body",
    "memory_body",
    "raw_memory_body",
    "prompt_body",
    "provider_payload",
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

  defp bounded_attrs(attrs, additions) do
    with :ok <- reject_raw_payload(attrs) do
      {:ok,
       attrs
       |> Map.merge(additions)
       |> Map.put_new(:redaction_posture, "bounded_refs_only")
       |> ExportBounds.bound_map!(surface: :span_attributes)}
    end
  end

  defp reject_raw_payload(attrs) do
    case Enum.find(@raw_payload_keys, &Map.has_key?(attrs, &1)) do
      nil -> :ok
      key -> {:error, {:raw_ai_platform_trace_payload_forbidden, key}}
    end
  end
end
