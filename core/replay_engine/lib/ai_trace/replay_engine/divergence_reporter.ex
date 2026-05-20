defmodule AITrace.ReplayEngine.DivergenceReporter do
  @moduledoc false

  @spec projection_divergences(map(), map()) :: [map()]
  def projection_divergences(emit_projection, causal_projection) do
    projection_keys =
      emit_projection
      |> Map.keys()
      |> Kernel.++(Map.keys(causal_projection))
      |> Enum.uniq()
      |> Enum.sort()

    projection_keys
    |> Enum.flat_map(fn projection_key ->
      if Map.get(emit_projection, projection_key) == Map.get(causal_projection, projection_key) do
        []
      else
        [
          %{
            phase: :projection_replay,
            projection_key: projection_key,
            severity: :regress,
            remediation_class: :review_reducer_ordering
          }
        ]
      end
    end)
  end
end
