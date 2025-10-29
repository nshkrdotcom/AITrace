defmodule AITrace.Trace do
  @moduledoc """
  A Trace represents the complete record of a single transaction.

  A trace contains:
  - A unique trace_id
  - A collection of all spans that occurred during the transaction
  - Metadata about the trace itself
  - Creation timestamp
  """

  alias AITrace.Span

  @type t :: %__MODULE__{
          trace_id: String.t(),
          spans: list(Span.t()),
          metadata: map(),
          created_at: integer()
        }

  defstruct [:trace_id, :created_at, spans: [], metadata: %{}]

  @doc """
  Creates a new trace with the given trace_id.

  ## Examples

      iex> trace = AITrace.Trace.new("trace_123")
      iex> trace.trace_id
      "trace_123"
      iex> trace.spans
      []
  """
  @spec new(String.t()) :: t()
  def new(trace_id) when is_binary(trace_id) do
    %__MODULE__{
      trace_id: trace_id,
      spans: [],
      metadata: %{},
      created_at: System.monotonic_time(:microsecond)
    }
  end

  @doc """
  Adds a span to the trace.

  ## Examples

      iex> trace = AITrace.Trace.new("trace_123")
      iex> span = AITrace.Span.new("operation")
      iex> trace = AITrace.Trace.add_span(trace, span)
      iex> length(trace.spans)
      1
  """
  @spec add_span(t(), Span.t()) :: t()
  def add_span(%__MODULE__{} = trace, %Span{} = span) do
    %{trace | spans: trace.spans ++ [span]}
  end

  @doc """
  Retrieves a span by its span_id.

  ## Examples

      iex> trace = AITrace.Trace.new("trace_123")
      iex> span = AITrace.Span.new("operation")
      iex> trace = AITrace.Trace.add_span(trace, span)
      iex> retrieved = AITrace.Trace.get_span(trace, span.span_id)
      iex> retrieved == span
      true
  """
  @spec get_span(t(), String.t()) :: Span.t() | nil
  def get_span(%__MODULE__{} = trace, span_id) do
    Enum.find(trace.spans, fn span -> span.span_id == span_id end)
  end

  @doc """
  Adds or merges metadata into the trace.

  ## Examples

      iex> trace = AITrace.Trace.new("trace_123")
      iex> trace = AITrace.Trace.with_metadata(trace, %{user_id: 42})
      iex> trace.metadata
      %{user_id: 42}
  """
  @spec with_metadata(t(), map()) :: t()
  def with_metadata(%__MODULE__{} = trace, metadata) when is_map(metadata) do
    %{trace | metadata: Map.merge(trace.metadata, metadata)}
  end

  @doc """
  Returns all root spans (spans with no parent).

  ## Examples

      iex> trace = AITrace.Trace.new("trace_123")
      iex> root = AITrace.Span.new("root")
      iex> trace = AITrace.Trace.add_span(trace, root)
      iex> roots = AITrace.Trace.get_root_spans(trace)
      iex> length(roots)
      1
  """
  @spec get_root_spans(t()) :: list(Span.t())
  def get_root_spans(%__MODULE__{} = trace) do
    Enum.filter(trace.spans, fn span -> span.parent_span_id == nil end)
  end

  @doc """
  Returns all child spans of a given parent span_id.

  ## Examples

      iex> trace = AITrace.Trace.new("trace_123")
      iex> root = AITrace.Span.new("root")
      iex> child = AITrace.Span.new("child", root.span_id)
      iex> trace = trace |> AITrace.Trace.add_span(root) |> AITrace.Trace.add_span(child)
      iex> children = AITrace.Trace.get_children(trace, root.span_id)
      iex> length(children)
      1
  """
  @spec get_children(t(), String.t()) :: list(Span.t())
  def get_children(%__MODULE__{} = trace, parent_span_id) do
    Enum.filter(trace.spans, fn span -> span.parent_span_id == parent_span_id end)
  end
end
