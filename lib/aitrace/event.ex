defmodule AITrace.Event do
  @moduledoc """
  An Event represents a point-in-time annotation within a Span.

  Events capture notable occurrences that aren't timed operations, such as:
  - State changes
  - Validation failures
  - Cache hits/misses
  - Tool errors
  """

  @type t :: %__MODULE__{
          name: String.t(),
          timestamp: integer(),
          attributes: map()
        }

  defstruct [:name, :timestamp, attributes: %{}]

  @doc """
  Creates a new event with a name and attributes.

  ## Examples

      iex> event = AITrace.Event.new("cache_miss", %{key: "user_123"})
      iex> event.name
      "cache_miss"
      iex> event.attributes
      %{key: "user_123"}
  """
  @spec new(String.t(), map()) :: t()
  def new(name, attributes \\ %{}) when is_binary(name) and is_map(attributes) do
    %__MODULE__{
      name: name,
      timestamp: System.monotonic_time(:microsecond),
      attributes: attributes
    }
  end
end
