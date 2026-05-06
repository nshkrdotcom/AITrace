defmodule AITrace.ReplayEngine do
  @moduledoc """
  Deterministic replay execution against past AITrace traces.
  """

  alias AITrace.{ReplayContracts, Span, Trace}

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
end
