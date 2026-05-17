defmodule AITrace.ReplayEngine do
  @moduledoc """
  Deterministic replay execution against past AITrace traces.
  """

  alias AITrace.{ReplayContracts, Span, Trace}
  alias AITrace.ReplayContracts.LineageReplayEvent

  @operator_actions %{
    clean: "accept",
    diverged: "review",
    denied: "reject",
    inconclusive: "review"
  }

  @spec replay(map() | ReplayContracts.ReplayRequest.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def replay(request_or_attrs, opts \\ []) when is_list(opts) do
    with {:ok, request} <- normalize_request(request_or_attrs),
         :ok <- authorize_replay(request, opts),
         :ok <- suppress_live_effects(opts),
         {:ok, source_trace} <- source_trace(request, opts),
         :ok <- same_tenant_trace(request, source_trace) do
      replay_trace = reconstruct_trace(source_trace, request)
      divergences = detect_divergences(source_trace, replay_trace, request, opts)
      decision_class = decision_class(divergences)

      with {:ok, bundle} <-
             bundle(request, source_trace, replay_trace, divergences, decision_class) do
        {:ok,
         %{
           request: request,
           source_trace: source_trace,
           replay_trace: replay_trace,
           divergences: divergences,
           bundle: bundle,
           side_effects_invoked?: false,
           cost_class: :replay
         }}
      end
    end
  end

  @spec replay_lineage_events([map() | LineageReplayEvent.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def replay_lineage_events(events, opts \\ [])

  def replay_lineage_events(events, opts) when is_list(events) and is_list(opts) do
    with {:ok, normalized} <- ReplayContracts.lineage_replay_events(events),
         :ok <- unique_event_refs(normalized),
         :ok <- required_event_kinds(normalized, Keyword.get(opts, :required_event_kinds, [])),
         :ok <- complete_predecessors(normalized),
         {:ok, causal_order} <- causal_order(normalized) do
      emit_projection = reduce_lineage_projection(normalized)
      causal_projection = reduce_lineage_projection(causal_order)
      projection_divergences = projection_divergences(emit_projection, causal_projection)

      {:ok,
       %{
         emit_order_event_refs: Enum.map(normalized, & &1.event_ref),
         causal_order_event_refs: Enum.map(causal_order, & &1.event_ref),
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

  def replay_lineage_events(_events, _opts), do: {:error, :invalid_lineage_replay_events}

  defp normalize_request(%ReplayContracts.ReplayRequest{} = request), do: {:ok, request}
  defp normalize_request(attrs) when is_map(attrs), do: ReplayContracts.replay_request(attrs)
  defp normalize_request(_attrs), do: {:error, :invalid_replay_request}

  defp authorize_replay(request, opts) do
    allowed = Keyword.get(opts, :authorized_tenants, [request.tenant_ref])

    if request.tenant_ref in allowed do
      :ok
    else
      {:error, :unauthorized_replay}
    end
  end

  defp suppress_live_effects(opts) do
    if Keyword.get(opts, :live_provider_effect?, false) do
      {:error, :replay_live_provider_effect_forbidden}
    else
      :ok
    end
  end

  defp source_trace(request, opts) do
    store = Keyword.get(opts, :trace_store, %{})

    case Map.get(store, request.source_trace_id) || Keyword.get(opts, :source_trace) do
      %Trace{} = trace -> {:ok, trace}
      _other -> {:error, :missing_source_trace}
    end
  end

  defp same_tenant_trace(request, %Trace{} = trace) do
    case Map.get(trace.metadata, :tenant_ref) || Map.get(trace.metadata, "tenant_ref") do
      nil -> :ok
      tenant_ref when tenant_ref == request.tenant_ref -> :ok
      _tenant_ref -> {:error, :cross_tenant_replay_forbidden}
    end
  end

  defp reconstruct_trace(%Trace{} = source_trace, request) do
    replay_trace_id = "replay://" <> source_trace.trace_id

    %Trace{
      source_trace
      | trace_id: replay_trace_id,
        trace_id_source: %{kind: "replay_trace", source_trace_id: source_trace.trace_id},
        spans: Enum.map(source_trace.spans, &replay_span(&1, replay_trace_id)),
        metadata:
          source_trace.metadata
          |> Map.put(:replay_mode, request.replay_mode)
          |> Map.put(:source_trace_id, source_trace.trace_id)
          |> Map.put(:replay_cost_class, :replay)
          |> Map.put(:replay_addressable?, true)
    }
  end

  defp replay_span(%Span{} = span, replay_trace_id) do
    %Span{
      span
      | span_id: replay_span_id(span.span_id),
        span_id_source: %{kind: "replay_span", source_span_id: span.span_id},
        parent_span_id: replay_parent_span_id(span.parent_span_id),
        parent_span_id_source: replay_parent_source(span.parent_span_id),
        attributes:
          span.attributes
          |> Map.put(:replay_trace_ref, replay_trace_id)
          |> Map.put(:source_span_ref, span.span_id)
          |> Map.put(:side_effect_policy, :suppress)
    }
  end

  defp replay_span_id(span_id), do: "replay-span://" <> span_id
  defp replay_parent_span_id(nil), do: nil
  defp replay_parent_span_id(parent_span_id), do: replay_span_id(parent_span_id)
  defp replay_parent_source(nil), do: nil

  defp replay_parent_source(parent_span_id),
    do: %{kind: "replay_parent_span", source_span_id: parent_span_id}

  defp detect_divergences(source_trace, replay_trace, request, opts) do
    []
    |> add_span_divergences(source_trace, replay_trace)
    |> add_variant_divergence(request)
    |> add_injected_divergences(opts)
    |> Enum.sort_by(&divergence_sort_key/1)
  end

  defp add_span_divergences(divergences, source_trace, replay_trace) do
    source_count = length(source_trace.spans)
    replay_count = length(replay_trace.spans)

    cond do
      source_count == replay_count ->
        divergences

      source_count > replay_count ->
        [
          divergence(:provider_response, :regress, "missing_span", "source", "replay")
          | divergences
        ]

      true ->
        [divergence(:provider_response, :warn, "extra_span", "source", "replay") | divergences]
    end
  end

  defp add_variant_divergence(divergences, %{variant_overrides: overrides})
       when map_size(overrides) == 0 do
    divergences
  end

  defp add_variant_divergence(divergences, %{replay_mode: replay_mode}) do
    phase = variant_phase(replay_mode)
    [divergence(phase, :warn, "variant_override", "source", "replay") | divergences]
  end

  defp add_injected_divergences(divergences, opts) do
    opts
    |> Keyword.get(:inject_divergences, [])
    |> Enum.reduce(divergences, fn attrs, acc ->
      [divergence_from_attrs(attrs) | acc]
    end)
  end

  defp divergence_from_attrs(attrs) when is_map(attrs) do
    divergence(
      Map.get(attrs, :phase, :provider_response),
      Map.get(attrs, :severity, :regress),
      Map.get(attrs, :redacted_excerpt_class, "injected_divergence"),
      Map.get(attrs, :source_span_ref, "source"),
      Map.get(attrs, :replay_span_ref, "replay")
    )
  end

  defp divergence_from_attrs(_attrs),
    do: divergence(:provider_response, :regress, "injected_divergence", "source", "replay")

  defp divergence(phase, severity, excerpt_class, source_span_ref, replay_span_ref) do
    {:ok, marker} =
      ReplayContracts.replay_divergence(%{
        divergence_ref: "replay-divergence://#{phase}/#{severity}/#{excerpt_class}",
        phase: phase,
        severity: severity,
        redacted_excerpt_class: "aitrace.redaction.replay.#{excerpt_class}.v1",
        remediation_class: remediation(severity),
        source_span_ref: source_span_ref,
        replay_span_ref: replay_span_ref
      })

    marker
  end

  defp divergence_sort_key(divergence),
    do: {Atom.to_string(divergence.phase), divergence.source_span_ref}

  defp variant_phase(:prompt_variant), do: :prompt_resolve
  defp variant_phase(:guard_variant), do: :guard_decision
  defp variant_phase(:memory_variant), do: :memory_access
  defp variant_phase(_mode), do: :provider_response

  defp remediation(:block), do: :operator_decision
  defp remediation(:regress), do: :review
  defp remediation(_severity), do: :none

  defp decision_class([]), do: :clean
  defp decision_class(_divergences), do: :diverged

  defp bundle(request, source_trace, replay_trace, divergences, decision_class) do
    ReplayContracts.replay_bundle(%{
      tenant_ref: request.tenant_ref,
      authority_ref: request.authority_ref,
      installation_ref: request.installation_ref,
      idempotency_key: request.idempotency_key,
      trace_ref: request.trace_ref,
      source_trace_ref: "trace://" <> source_trace.trace_id,
      replay_trace_ref: "trace://" <> replay_trace.trace_id,
      divergence_refs: Enum.map(divergences, & &1.divergence_ref),
      decision_class: decision_class,
      cost_class: :replay,
      operator_action: Map.fetch!(@operator_actions, decision_class),
      release_manifest_ref: request.release_manifest_ref
    })
  end

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

  defp lineage_sort_key(event),
    do: {event.causal_order, event.projection_order_key, event.event_ref}

  defp reduce_lineage_projection(events) do
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

    if lineage_sort_key(event) >= current_sort_key do
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

  defp projection_divergences(emit_projection, causal_projection) do
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
