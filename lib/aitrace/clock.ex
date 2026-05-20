defmodule AITrace.Clock do
  @moduledoc """
  Local clock-domain helpers for AITrace timing evidence.

  Monotonic values are local-duration evidence only. Exported traces and spans
  also carry wall-clock timestamps and a clock-domain descriptor.
  """

  @spec monotonic_time() :: integer()
  def monotonic_time, do: System.monotonic_time(:microsecond)

  @spec wall_time() :: DateTime.t()
  def wall_time, do: DateTime.utc_now()

  @spec clock_domain(keyword()) :: map()
  def clock_domain(opts \\ []) do
    runtime_identity = runtime_identity(opts)

    %{
      node: runtime_identity.node,
      runtime_id: runtime_identity.runtime_id,
      monotonic_unit: "microsecond"
    }
  end

  @spec duration_microseconds(integer(), integer() | nil) :: integer() | nil
  def duration_microseconds(_start_time, nil), do: nil
  def duration_microseconds(start_time, end_time), do: end_time - start_time

  @spec wall_time_iso8601(DateTime.t() | nil) :: String.t() | nil
  def wall_time_iso8601(nil), do: nil
  def wall_time_iso8601(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)

  defp runtime_identity(opts) do
    opts
    |> Keyword.get(:runtime_identity, AITrace.RuntimeIdentity)
    |> AITrace.RuntimeIdentity.snapshot()
  end
end
