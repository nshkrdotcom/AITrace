defmodule AITrace.ReplayEngine.LineageReplayRunner do
  @moduledoc false

  alias AITrace.ReplayContracts
  alias AITrace.ReplayEngine.{DivergenceReporter, LineageProjectionReducer, LineageSorter}

  @spec replay([map() | ReplayContracts.LineageReplayEvent.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def replay(events, opts) when is_list(events) and is_list(opts) do
    with {:ok, normalized} <- ReplayContracts.lineage_replay_events(events),
         {:ok, trace_policy} <- trace_level_policy(opts),
         :ok <- trace_level_policy_satisfied(normalized, trace_policy),
         {:ok, causal_order} <-
           LineageSorter.validate_and_order(
             normalized,
             Keyword.get(opts, :required_event_kinds, [])
           ) do
      emit_projection = LineageProjectionReducer.reduce(normalized)
      causal_projection = LineageProjectionReducer.reduce(causal_order)

      projection_divergences =
        DivergenceReporter.projection_divergences(emit_projection, causal_projection)

      {:ok,
       %{
         emit_order_event_refs: Enum.map(normalized, & &1.event_ref),
         causal_order_event_refs: Enum.map(causal_order, & &1.event_ref),
         trace_level_expectations: LineageProjectionReducer.trace_level_expectations(normalized),
         trace_level_policy: trace_level_policy_summary(trace_policy),
         order_diverged?:
           Enum.map(normalized, & &1.event_ref) != Enum.map(causal_order, & &1.event_ref),
         projection_outputs: %{
           emit_order: emit_projection,
           causal_order: causal_projection
         },
         projection_diverged?: projection_divergences != [],
         divergences: projection_divergences,
         missing_predecessors: [],
         replay_complete?: true
       }}
    end
  end

  defp trace_level_policy(opts) do
    case Keyword.get(opts, :trace_profile) do
      nil -> {:ok, nil}
      profile -> ReplayContracts.trace_level_policy(profile)
    end
  end

  defp trace_level_policy_satisfied(_events, nil), do: :ok

  defp trace_level_policy_satisfied(events, policy) do
    with :ok <- allowed_trace_levels(events, policy),
         :ok <- required_trace_level_present(events, policy) do
      required_trace_level_event_kinds(events, policy)
    end
  end

  defp allowed_trace_levels(events, policy) do
    case Enum.find(events, &(&1.trace_level not in policy.allowed_trace_levels)) do
      nil -> :ok
      event -> {:error, {:disallowed_trace_level, policy.profile, event.trace_level}}
    end
  end

  defp required_trace_level_present(events, policy) do
    if Enum.any?(events, &(&1.trace_level == policy.required_trace_level)) do
      :ok
    else
      {:error, {:missing_trace_level, policy.profile, policy.required_trace_level}}
    end
  end

  defp required_trace_level_event_kinds(events, policy) do
    missing =
      Enum.reject(policy.required_event_kinds, fn event_kind ->
        Enum.any?(
          events,
          &(&1.event_kind == event_kind and &1.trace_level == policy.required_trace_level)
        )
      end)

    case missing do
      [] ->
        :ok

      missing ->
        {:error,
         {:missing_trace_level_event_kinds, policy.profile, policy.required_trace_level, missing}}
    end
  end

  defp trace_level_policy_summary(nil), do: nil

  defp trace_level_policy_summary(policy) do
    %{
      profile: policy.profile,
      default_trace_level: policy.default_trace_level,
      required_trace_level: policy.required_trace_level,
      allowed_trace_levels: policy.allowed_trace_levels,
      required_event_kinds: policy.required_event_kinds,
      requires_detailed_proof?: policy.requires_detailed_proof?,
      production_default?: policy.production_default?
    }
  end
end
