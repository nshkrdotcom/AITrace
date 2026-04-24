defmodule AITrace.Clock do
  @moduledoc """
  Local clock-domain helpers for AITrace timing evidence.

  Monotonic values are local-duration evidence only. Exported traces and spans
  also carry wall-clock timestamps and a clock-domain descriptor.
  """

  @runtime_key {__MODULE__, :runtime_id}

  @spec monotonic_time() :: integer()
  def monotonic_time, do: System.monotonic_time(:microsecond)

  @spec wall_time() :: DateTime.t()
  def wall_time, do: DateTime.utc_now()

  @spec clock_domain() :: map()
  def clock_domain do
    %{
      node: Atom.to_string(node()),
      runtime_id: runtime_id(),
      monotonic_unit: "microsecond"
    }
  end

  @spec duration_microseconds(integer(), integer() | nil) :: integer() | nil
  def duration_microseconds(_start_time, nil), do: nil
  def duration_microseconds(start_time, end_time), do: end_time - start_time

  @spec wall_time_iso8601(DateTime.t() | nil) :: String.t() | nil
  def wall_time_iso8601(nil), do: nil
  def wall_time_iso8601(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)

  defp runtime_id do
    case :persistent_term.get(@runtime_key, nil) do
      nil ->
        id = "#{node()}:#{System.system_time(:nanosecond)}:#{System.unique_integer([:positive])}"
        :persistent_term.put(@runtime_key, id)
        id

      id ->
        id
    end
  end
end
