defmodule AITrace.ReplayEngine.LineageSorter do
  @moduledoc false

  @spec validate_and_order([map()], [atom()]) :: {:ok, [map()]} | {:error, term()}
  def validate_and_order(events, required_kinds) do
    with :ok <- unique_event_refs(events),
         :ok <- required_event_kinds(events, required_kinds),
         :ok <- complete_predecessors(events) do
      causal_order(events)
    end
  end

  @spec lineage_sort_key(map()) :: {integer(), term(), String.t()}
  def lineage_sort_key(event),
    do: {event.causal_order, event.projection_order_key, event.event_ref}

  defp unique_event_refs(events) do
    frequencies = Enum.frequencies_by(events, & &1.event_ref)

    case frequencies |> Enum.filter(fn {_event_ref, count} -> count > 1 end) do
      [] ->
        :ok

      duplicate_refs ->
        {:error, {:duplicate_lineage_event_refs, Enum.map(duplicate_refs, &elem(&1, 0))}}
    end
  end

  defp required_event_kinds(_events, []), do: :ok

  defp required_event_kinds(events, required_kinds) when is_list(required_kinds) do
    observed = Map.new(events, &{&1.event_kind, true})

    missing =
      required_kinds
      |> Enum.reject(&Map.has_key?(observed, &1))
      |> Enum.sort_by(&Atom.to_string/1)

    case missing do
      [] -> :ok
      _missing -> {:error, {:missing_required_event_kinds, missing}}
    end
  end

  defp required_event_kinds(_events, _required_kinds),
    do: {:error, {:invalid_replay_field, :required_event_kinds}}

  defp complete_predecessors(events) do
    event_refs = Map.new(events, &{&1.event_ref, true})

    missing =
      events
      |> Enum.flat_map(fn event ->
        event.predecessor_event_refs
        |> Enum.reject(&Map.has_key?(event_refs, &1))
        |> Enum.map(&%{event_ref: event.event_ref, missing_predecessor_ref: &1})
      end)
      |> Enum.sort_by(&{&1.event_ref, &1.missing_predecessor_ref})

    case missing do
      [] -> :ok
      _missing -> {:error, {:missing_predecessor_events, missing}}
    end
  end

  defp causal_order(events) do
    events_by_ref = Map.new(events, &{&1.event_ref, &1})
    pending_refs = Map.new(events, &{&1.event_ref, true})
    emitted_refs = %{}
    ordered = []

    do_causal_order(events_by_ref, pending_refs, emitted_refs, ordered)
  end

  defp do_causal_order(events_by_ref, pending_refs, emitted_refs, ordered) do
    case map_size(pending_refs) do
      0 ->
        {:ok, Enum.reverse(ordered)}

      _pending_count ->
        ready =
          events_by_ref
          |> Map.values()
          |> Enum.filter(fn event ->
            Map.has_key?(pending_refs, event.event_ref) and
              Enum.all?(event.predecessor_event_refs, &Map.has_key?(emitted_refs, &1))
          end)
          |> Enum.sort_by(&lineage_sort_key/1)

        case ready do
          [] ->
            {:error, {:cyclic_lineage_events, pending_refs |> Map.keys() |> Enum.sort()}}

          [next | _rest] ->
            do_causal_order(
              events_by_ref,
              Map.delete(pending_refs, next.event_ref),
              Map.put(emitted_refs, next.event_ref, true),
              [next | ordered]
            )
        end
    end
  end
end
