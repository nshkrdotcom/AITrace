defmodule AITrace.Context do
  @moduledoc """
  An immutable context that carries trace and span identifiers through the call stack.

  The Context is the core mechanism for correlating telemetry data. It contains:
  - `trace_id`: A unique identifier for the entire trace/transaction
  - `span_id`: The current span within the trace (nil if not in a span)
  - `export_profile`: Export sinks captured when the trace context is created
  - `runtime_identity`: Runtime identity captured when the context is created
  - governed-effect refs: effect, command, authority, and receipt refs carried explicitly
  - `metadata`: Additional key-value metadata for the trace
  """

  @type t :: %__MODULE__{
          trace_id: String.t(),
          trace_id_source: map(),
          span_id: String.t() | nil,
          export_profile: AITrace.ExportProfile.t() | nil,
          runtime_identity: AITrace.RuntimeIdentity.snapshot(),
          effect_ref: String.t() | nil,
          command_ref: String.t() | nil,
          authority_ref: String.t() | nil,
          receipt_ref: String.t() | nil,
          metadata: map()
        }

  defstruct [
    :trace_id,
    :trace_id_source,
    :span_id,
    :export_profile,
    :runtime_identity,
    :effect_ref,
    :command_ref,
    :authority_ref,
    :receipt_ref,
    metadata: %{}
  ]

  @doc """
  Creates a new context with a generated trace_id.

  ## Examples

      iex> ctx = AITrace.Context.new()
      iex> is_binary(ctx.trace_id)
      true
      iex> ctx.span_id
      nil
  """
  @spec new() :: t()
  def new do
    trace_id = generate_id()

    %__MODULE__{
      trace_id: trace_id,
      trace_id_source: AITrace.Identifier.source!(:trace, trace_id, :aitrace_generated),
      span_id: nil,
      runtime_identity: AITrace.RuntimeIdentity.snapshot(),
      metadata: %{}
    }
  end

  @doc """
  Creates a new context with the provided trace_id.

  ## Examples

      iex> ctx = AITrace.Context.new("my_trace_123")
      iex> ctx.trace_id
      "my_trace_123"
  """
  @spec new(String.t()) :: t()
  def new(trace_id) when is_binary(trace_id) do
    %__MODULE__{
      trace_id: trace_id,
      trace_id_source: AITrace.Identifier.source!(:trace, trace_id, :external_alias),
      span_id: nil,
      runtime_identity: AITrace.RuntimeIdentity.snapshot(),
      metadata: %{}
    }
  end

  @doc """
  Returns a new context with the updated span_id.

  ## Examples

      iex> ctx = AITrace.Context.new()
      iex> new_ctx = AITrace.Context.with_span_id(ctx, "span_123")
      iex> new_ctx.span_id
      "span_123"
  """
  @spec with_span_id(t(), String.t()) :: t()
  def with_span_id(%__MODULE__{} = ctx, span_id) when is_binary(span_id) do
    %{ctx | span_id: span_id}
  end

  @doc """
  Returns a new context with merged metadata.

  ## Examples

      iex> ctx = AITrace.Context.new()
      iex> new_ctx = AITrace.Context.with_metadata(ctx, %{user_id: 42})
      iex> new_ctx.metadata
      %{user_id: 42}
  """
  @spec with_metadata(t(), map()) :: t()
  def with_metadata(%__MODULE__{} = ctx, metadata) when is_map(metadata) do
    %{ctx | metadata: Map.merge(ctx.metadata, metadata)}
  end

  @doc """
  Returns a new context with the export profile captured for trace finish.
  """
  @spec with_export_profile(t(), AITrace.ExportProfile.t()) :: t()
  def with_export_profile(%__MODULE__{} = ctx, %AITrace.ExportProfile{} = export_profile) do
    %{ctx | export_profile: export_profile}
  end

  @doc """
  Returns a new context with governed-effect refs carried as explicit fields.
  """
  @spec with_governed_effect_refs(t(), map() | keyword()) :: t()
  def with_governed_effect_refs(%__MODULE__{} = ctx, attrs)
      when is_map(attrs) or is_list(attrs) do
    refs = governed_effect_refs_from(attrs)

    %{
      ctx
      | effect_ref: refs.effect_ref,
        command_ref: refs.command_ref,
        authority_ref: refs.authority_ref,
        receipt_ref: refs.receipt_ref
    }
  end

  @doc """
  Returns the governed-effect refs carried by a context.
  """
  @spec governed_effect_refs(t()) :: map()
  def governed_effect_refs(%__MODULE__{} = ctx) do
    %{
      effect_ref: ctx.effect_ref,
      command_ref: ctx.command_ref,
      authority_ref: ctx.authority_ref,
      receipt_ref: ctx.receipt_ref
    }
  end

  @doc """
  Returns trace metadata derived from the explicit context.
  """
  @spec export_metadata(t()) :: map()
  def export_metadata(%__MODULE__{} = ctx) do
    ctx.metadata
    |> Map.merge(reject_nil_values(governed_effect_refs(ctx)))
    |> maybe_put_export_profile_ref(ctx.export_profile)
  end

  @doc """
  Retrieves a metadata value by key.

  ## Examples

      iex> ctx = AITrace.Context.new() |> AITrace.Context.with_metadata(%{user_id: 42})
      iex> AITrace.Context.get_metadata(ctx, :user_id)
      42
      iex> AITrace.Context.get_metadata(ctx, :missing, :default)
      :default
  """
  @spec get_metadata(t(), atom(), any()) :: any()
  def get_metadata(%__MODULE__{} = ctx, key, default \\ nil) do
    Map.get(ctx.metadata, key, default)
  end

  # Delegates generated trace id ownership to AITrace.Identifier.
  @spec generate_id() :: String.t()
  def generate_id, do: AITrace.Identifier.generate(:trace)

  defp governed_effect_refs_from(attrs) do
    attrs = normalize_attrs(attrs)

    %{
      effect_ref: ref!(attrs, :effect_ref),
      command_ref: ref!(attrs, :command_ref),
      authority_ref: ref!(attrs, :authority_ref),
      receipt_ref: ref!(attrs, :receipt_ref)
    }
  end

  defp normalize_attrs(attrs) when is_map(attrs), do: attrs

  defp normalize_attrs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      Map.new(attrs)
    else
      raise ArgumentError, "governed effect refs must be a keyword list or map"
    end
  end

  defp ref!(attrs, key) do
    value = Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

    if is_binary(value) and String.trim(value) != "" do
      value
    else
      raise ArgumentError, "#{key} must be a non-empty string"
    end
  end

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp maybe_put_export_profile_ref(metadata, %AITrace.ExportProfile{} = export_profile) do
    case Map.get(export_profile.metadata, :profile_ref) do
      nil -> metadata
      profile_ref -> Map.put(metadata, :export_profile_ref, profile_ref)
    end
  end

  defp maybe_put_export_profile_ref(metadata, _export_profile), do: metadata
end
