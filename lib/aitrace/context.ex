defmodule AITrace.Context do
  @moduledoc """
  An immutable context that carries trace and span identifiers through the call stack.

  The Context is the core mechanism for correlating telemetry data. It contains:
  - `trace_id`: A unique identifier for the entire trace/transaction
  - `span_id`: The current span within the trace (nil if not in a span)
  - `metadata`: Additional key-value metadata for the trace
  """

  @type t :: %__MODULE__{
          trace_id: String.t(),
          trace_id_source: map(),
          span_id: String.t() | nil,
          metadata: map()
        }

  defstruct [:trace_id, :trace_id_source, :span_id, metadata: %{}]

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
end
