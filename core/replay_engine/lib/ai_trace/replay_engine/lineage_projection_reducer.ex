defmodule AITrace.ReplayEngine.LineageProjectionReducer do
  @moduledoc false

  alias AITrace.ReplayEngine.LineageSorter

  @spec reduce([map()]) :: map()
  def reduce(events) do
    Enum.reduce(events, %{}, fn
      %{projection_visible?: false}, acc ->
        acc

      %{projection_key: nil}, acc ->
        acc

      event, acc ->
        Map.update(acc, event.projection_key, initial_projection_value(event), fn current ->
          merge_projection_value(current, event)
        end)
    end)
  end

  @spec trace_level_expectations([map()]) :: map()
  def trace_level_expectations(events) do
    events
    |> Enum.group_by(& &1.trace_level)
    |> Map.new(fn {trace_level, level_events} ->
      {trace_level,
       %{
         event_refs: level_events |> Enum.map(& &1.event_ref) |> Enum.sort(),
         retention_policy_refs: metadata_values(level_events, :retention_policy_ref),
         ttl_seconds: metadata_values(level_events, :ttl_seconds),
         emission_modes: metadata_values(level_events, :emission_mode),
         batch_refs: metadata_values(level_events, :batch_ref),
         emission_expectation_refs: metadata_values(level_events, :emission_expectation_ref)
       }}
    end)
  end

  defp metadata_values(events, field) do
    events
    |> Enum.map(&metadata_value(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort_by(&metadata_value_sort_key/1)
  end

  defp metadata_value(%{metadata_refs: metadata_refs}, field) do
    Map.get(metadata_refs, field) || Map.get(metadata_refs, Atom.to_string(field))
  end

  defp metadata_value_sort_key(value) when is_integer(value), do: {0, value}
  defp metadata_value_sort_key(value) when is_binary(value), do: {1, value}
  defp metadata_value_sort_key(value) when is_atom(value), do: {2, Atom.to_string(value)}
  defp metadata_value_sort_key(value), do: {3, inspect(value)}

  defp initial_projection_value(%{merge_semantics: :set_union} = event) do
    %{merge_semantics: :set_union, event_refs: [event.event_ref]}
  end

  defp initial_projection_value(%{merge_semantics: :map_merge_by_key} = event) do
    %{
      merge_semantics: :map_merge_by_key,
      entries: metadata_entries(event),
      event_refs: [event.event_ref]
    }
  end

  defp initial_projection_value(%{merge_semantics: :max} = event) do
    %{merge_semantics: :max, causal_order: event.causal_order, event_ref: event.event_ref}
  end

  defp initial_projection_value(%{merge_semantics: :min} = event) do
    %{merge_semantics: :min, causal_order: event.causal_order, event_ref: event.event_ref}
  end

  defp initial_projection_value(%{merge_semantics: :last_write_by_causal_order} = event) do
    %{
      merge_semantics: :last_write_by_causal_order,
      causal_order: event.causal_order,
      projection_order_key: event.projection_order_key,
      event_ref: event.event_ref
    }
  end

  defp initial_projection_value(%{merge_semantics: :append_by_projection_order} = event) do
    %{
      merge_semantics: :append_by_projection_order,
      event_refs: [event.event_ref],
      ordered_event_refs: [{event.projection_order_key, event.event_ref}]
    }
  end

  defp initial_projection_value(%{merge_semantics: :state_transition} = event) do
    %{
      merge_semantics: :state_transition,
      current_event_ref: event.event_ref,
      applied_event_refs: [event.event_ref]
    }
  end

  defp initial_projection_value(event) do
    %{merge_semantics: event.merge_semantics, event_refs: [event.event_ref]}
  end

  defp merge_projection_value(%{merge_semantics: :set_union} = current, event) do
    %{
      current
      | event_refs:
          current.event_refs |> Kernel.++([event.event_ref]) |> Enum.uniq() |> Enum.sort()
    }
  end

  defp merge_projection_value(%{merge_semantics: :map_merge_by_key} = current, event) do
    %{
      current
      | entries: Map.merge(current.entries, metadata_entries(event)),
        event_refs:
          current.event_refs |> Kernel.++([event.event_ref]) |> Enum.uniq() |> Enum.sort()
    }
  end

  defp merge_projection_value(%{merge_semantics: :max} = current, event) do
    if event.causal_order > current.causal_order do
      %{current | causal_order: event.causal_order, event_ref: event.event_ref}
    else
      current
    end
  end

  defp merge_projection_value(%{merge_semantics: :min} = current, event) do
    if event.causal_order < current.causal_order do
      %{current | causal_order: event.causal_order, event_ref: event.event_ref}
    else
      current
    end
  end

  defp merge_projection_value(%{merge_semantics: :last_write_by_causal_order} = current, event) do
    current_sort_key = {current.causal_order, current.projection_order_key, current.event_ref}

    if LineageSorter.lineage_sort_key(event) >= current_sort_key do
      %{
        current
        | causal_order: event.causal_order,
          projection_order_key: event.projection_order_key,
          event_ref: event.event_ref
      }
    else
      current
    end
  end

  defp merge_projection_value(%{merge_semantics: :append_by_projection_order} = current, event) do
    ordered_event_refs =
      current.ordered_event_refs
      |> Kernel.++([{event.projection_order_key, event.event_ref}])
      |> Enum.sort()

    %{
      current
      | ordered_event_refs: ordered_event_refs,
        event_refs: Enum.map(ordered_event_refs, &elem(&1, 1))
    }
  end

  defp merge_projection_value(%{merge_semantics: :state_transition} = current, event) do
    %{
      current
      | current_event_ref: event.event_ref,
        applied_event_refs: current.applied_event_refs ++ [event.event_ref]
    }
  end

  defp merge_projection_value(current, event) do
    %{
      current
      | event_refs:
          current.event_refs |> Kernel.++([event.event_ref]) |> Enum.uniq() |> Enum.sort()
    }
  end

  defp metadata_entries(%{metadata_refs: metadata_refs}) do
    Map.get(metadata_refs, :projection_entries) || Map.get(metadata_refs, "projection_entries") ||
      %{}
  end
end
