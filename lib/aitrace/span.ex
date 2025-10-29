defmodule AITrace.Span do
  @moduledoc """
  A Span represents a timed operation within a trace.

  Spans form a tree structure through parent-child relationships and contain:
  - Timing information (start_time, end_time)
  - Hierarchical information (span_id, parent_span_id)
  - Metadata (attributes)
  - Point-in-time events
  - Status (ok, error)
  """

  alias AITrace.Event

  @type status :: :ok | :error

  @type t :: %__MODULE__{
          span_id: String.t(),
          parent_span_id: String.t() | nil,
          name: String.t(),
          start_time: integer(),
          end_time: integer() | nil,
          attributes: map(),
          events: list(Event.t()),
          status: status()
        }

  defstruct [
    :span_id,
    :parent_span_id,
    :name,
    :start_time,
    :end_time,
    attributes: %{},
    events: [],
    status: :ok
  ]

  @doc """
  Creates a new span with the given name.

  ## Examples

      iex> span = AITrace.Span.new("llm_call")
      iex> is_binary(span.span_id)
      true
      iex> span.name
      "llm_call"
  """
  @spec new(String.t()) :: t()
  def new(name) when is_binary(name) do
    %__MODULE__{
      span_id: generate_id(),
      parent_span_id: nil,
      name: name,
      start_time: System.monotonic_time(:microsecond),
      end_time: nil,
      attributes: %{},
      events: [],
      status: :ok
    }
  end

  @doc """
  Creates a new span with the given name and parent span ID.

  ## Examples

      iex> span = AITrace.Span.new("child_operation", "parent_123")
      iex> span.parent_span_id
      "parent_123"
  """
  @spec new(String.t(), String.t()) :: t()
  def new(name, parent_span_id) when is_binary(name) and is_binary(parent_span_id) do
    %__MODULE__{
      span_id: generate_id(),
      parent_span_id: parent_span_id,
      name: name,
      start_time: System.monotonic_time(:microsecond),
      end_time: nil,
      attributes: %{},
      events: [],
      status: :ok
    }
  end

  @doc """
  Marks the span as finished by setting its end_time.

  ## Examples

      iex> span = AITrace.Span.new("operation")
      iex> finished = AITrace.Span.finish(span)
      iex> is_integer(finished.end_time)
      true
  """
  @spec finish(t()) :: t()
  def finish(%__MODULE__{} = span) do
    %{span | end_time: System.monotonic_time(:microsecond)}
  end

  @doc """
  Adds or merges attributes into the span.

  ## Examples

      iex> span = AITrace.Span.new("operation")
      iex> span = AITrace.Span.with_attributes(span, %{user_id: 42})
      iex> span.attributes
      %{user_id: 42}
  """
  @spec with_attributes(t(), map()) :: t()
  def with_attributes(%__MODULE__{} = span, attributes) when is_map(attributes) do
    %{span | attributes: Map.merge(span.attributes, attributes)}
  end

  @doc """
  Adds an event to the span.

  ## Examples

      iex> span = AITrace.Span.new("operation")
      iex> event = %AITrace.Event{name: "cache_hit", timestamp: System.monotonic_time(:microsecond)}
      iex> span = AITrace.Span.add_event(span, event)
      iex> length(span.events)
      1
  """
  @spec add_event(t(), Event.t()) :: t()
  def add_event(%__MODULE__{} = span, %Event{} = event) do
    %{span | events: span.events ++ [event]}
  end

  @doc """
  Sets the status of the span.

  ## Examples

      iex> span = AITrace.Span.new("operation")
      iex> span = AITrace.Span.with_status(span, :error)
      iex> span.status
      :error
  """
  @spec with_status(t(), status()) :: t()
  def with_status(%__MODULE__{} = span, status) when status in [:ok, :error] do
    %{span | status: status}
  end

  @doc """
  Returns the duration of the span in microseconds.
  Returns nil if the span has not been finished.

  ## Examples

      iex> span = AITrace.Span.new("operation") |> AITrace.Span.finish()
      iex> is_integer(AITrace.Span.duration(span))
      true
  """
  @spec duration(t()) :: integer() | nil
  def duration(%__MODULE__{end_time: nil}), do: nil

  def duration(%__MODULE__{start_time: start_time, end_time: end_time}) do
    end_time - start_time
  end

  # Generates a unique ID (32 character hex string)
  @spec generate_id() :: String.t()
  defp generate_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end
