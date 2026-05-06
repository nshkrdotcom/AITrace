defmodule AITrace.ReplayContracts do
  @moduledoc """
  Ref-only replay contracts.

  Constructors accept atom or string keys from DTO boundaries, validate bounded
  vocabularies, and reject raw payload-bearing fields.
  """

  @replay_modes [
    :exact,
    :prompt_variant,
    :model_variant,
    :policy_variant,
    :guard_variant,
    :memory_variant
  ]
  @side_effect_policies [:suppress, :simulate_with_fixture, :fixture_per_capability]
  @divergence_phases [
    :prompt_resolve,
    :tool_call_payload,
    :guard_decision,
    :memory_access,
    :provider_response
  ]
  @divergence_severities [:info, :warn, :regress, :block]
  @remediation_classes [:none, :review, :rollback_prompt, :update_fixture, :operator_decision]
  @decision_classes [:clean, :diverged, :denied, :inconclusive]
  @cost_classes [:replay]

  @request_required [
    :tenant_ref,
    :authority_ref,
    :installation_ref,
    :idempotency_key,
    :trace_ref,
    :source_trace_id,
    :replay_mode,
    :side_effect_policy,
    :persistence_ref,
    :release_manifest_ref
  ]
  @bundle_required [
    :tenant_ref,
    :authority_ref,
    :installation_ref,
    :idempotency_key,
    :trace_ref,
    :source_trace_ref,
    :replay_trace_ref,
    :decision_class,
    :cost_class,
    :operator_action,
    :release_manifest_ref
  ]
  @divergence_required [
    :phase,
    :severity,
    :redacted_excerpt_class,
    :remediation_class,
    :source_span_ref,
    :replay_span_ref
  ]
  @raw_payload_keys [
    :body,
    :raw_body,
    :payload,
    :raw_payload,
    :prompt_body,
    :raw_prompt,
    :memory_body,
    :raw_memory_body,
    :provider_payload,
    :provider_response,
    :model_output,
    :raw_output,
    :secret,
    :token,
    "body",
    "raw_body",
    "payload",
    "raw_payload",
    "prompt_body",
    "raw_prompt",
    "memory_body",
    "raw_memory_body",
    "provider_payload",
    "provider_response",
    "model_output",
    "raw_output",
    "secret",
    "token"
  ]

  defmodule ReplayRequest do
    @moduledoc "Replay request carrying only refs and bounded variant controls."
    @enforce_keys [
      :tenant_ref,
      :authority_ref,
      :installation_ref,
      :idempotency_key,
      :trace_ref,
      :source_trace_id,
      :replay_mode,
      :variant_overrides,
      :side_effect_policy,
      :divergence_thresholds,
      :persistence_ref,
      :release_manifest_ref
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            tenant_ref: String.t(),
            authority_ref: String.t(),
            installation_ref: String.t(),
            idempotency_key: String.t(),
            trace_ref: String.t(),
            source_trace_id: String.t(),
            replay_mode: atom(),
            variant_overrides: map(),
            side_effect_policy: atom(),
            divergence_thresholds: map(),
            persistence_ref: String.t(),
            release_manifest_ref: String.t()
          }
  end

  defmodule ReplayDivergence do
    @moduledoc "Bounded replay divergence marker."
    @enforce_keys [
      :phase,
      :severity,
      :redacted_excerpt_class,
      :remediation_class,
      :source_span_ref,
      :replay_span_ref
    ]
    defstruct [:divergence_ref | @enforce_keys]

    @type t :: %__MODULE__{
            divergence_ref: String.t() | nil,
            phase: atom(),
            severity: atom(),
            redacted_excerpt_class: String.t(),
            remediation_class: atom(),
            source_span_ref: String.t(),
            replay_span_ref: String.t()
          }
  end

  defmodule ReplayBundle do
    @moduledoc "Replay bundle with replay cost class and bounded divergence refs."
    @enforce_keys [
      :tenant_ref,
      :authority_ref,
      :installation_ref,
      :idempotency_key,
      :trace_ref,
      :source_trace_ref,
      :replay_trace_ref,
      :divergence_refs,
      :decision_class,
      :cost_class,
      :operator_action,
      :release_manifest_ref
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            tenant_ref: String.t(),
            authority_ref: String.t(),
            installation_ref: String.t(),
            idempotency_key: String.t(),
            trace_ref: String.t(),
            source_trace_ref: String.t(),
            replay_trace_ref: String.t(),
            divergence_refs: [String.t()],
            decision_class: atom(),
            cost_class: atom(),
            operator_action: String.t(),
            release_manifest_ref: String.t()
          }
  end

  @spec replay_modes() :: [atom()]
  def replay_modes, do: @replay_modes

  @spec side_effect_policies() :: [atom()]
  def side_effect_policies, do: @side_effect_policies

  @spec divergence_phases() :: [atom()]
  def divergence_phases, do: @divergence_phases

  @spec replay_request(map()) :: {:ok, ReplayRequest.t()} | {:error, term()}
  def replay_request(attrs) when is_map(attrs) do
    with :ok <- reject_raw_payload(attrs),
         :ok <- required_strings(attrs, @request_required -- [:replay_mode, :side_effect_policy]),
         :ok <- same_tenant_source(attrs),
         {:ok, mode} <- member(attrs, :replay_mode, @replay_modes),
         {:ok, policy} <- member(attrs, :side_effect_policy, @side_effect_policies),
         {:ok, variant_overrides} <- map_field(attrs, :variant_overrides, %{}),
         {:ok, divergence_thresholds} <- map_field(attrs, :divergence_thresholds, %{}) do
      {:ok,
       %ReplayRequest{
         tenant_ref: fetch!(attrs, :tenant_ref),
         authority_ref: fetch!(attrs, :authority_ref),
         installation_ref: fetch!(attrs, :installation_ref),
         idempotency_key: fetch!(attrs, :idempotency_key),
         trace_ref: fetch!(attrs, :trace_ref),
         source_trace_id: fetch!(attrs, :source_trace_id),
         replay_mode: mode,
         variant_overrides: variant_overrides,
         side_effect_policy: policy,
         divergence_thresholds: divergence_thresholds,
         persistence_ref: fetch!(attrs, :persistence_ref),
         release_manifest_ref: fetch!(attrs, :release_manifest_ref)
       }}
    end
  end

  def replay_request(_attrs), do: {:error, :invalid_replay_request}

  @spec replay_divergence(map()) :: {:ok, ReplayDivergence.t()} | {:error, term()}
  def replay_divergence(attrs) when is_map(attrs) do
    with :ok <- reject_raw_payload(attrs),
         :ok <-
           required_strings(
             attrs,
             @divergence_required -- [:phase, :severity, :remediation_class]
           ),
         {:ok, phase} <- member(attrs, :phase, @divergence_phases),
         {:ok, severity} <- member(attrs, :severity, @divergence_severities),
         {:ok, remediation} <- member(attrs, :remediation_class, @remediation_classes) do
      {:ok,
       %ReplayDivergence{
         divergence_ref: fetch(attrs, :divergence_ref),
         phase: phase,
         severity: severity,
         redacted_excerpt_class: fetch!(attrs, :redacted_excerpt_class),
         remediation_class: remediation,
         source_span_ref: fetch!(attrs, :source_span_ref),
         replay_span_ref: fetch!(attrs, :replay_span_ref)
       }}
    end
  end

  def replay_divergence(_attrs), do: {:error, :invalid_replay_divergence}

  @spec replay_bundle(map()) :: {:ok, ReplayBundle.t()} | {:error, term()}
  def replay_bundle(attrs) when is_map(attrs) do
    with :ok <- reject_raw_payload(attrs),
         :ok <- required_strings(attrs, @bundle_required -- [:decision_class, :cost_class]),
         {:ok, decision} <- member(attrs, :decision_class, @decision_classes),
         {:ok, cost_class} <- member(attrs, :cost_class, @cost_classes),
         {:ok, divergence_refs} <- string_list_field(attrs, :divergence_refs, []) do
      {:ok,
       %ReplayBundle{
         tenant_ref: fetch!(attrs, :tenant_ref),
         authority_ref: fetch!(attrs, :authority_ref),
         installation_ref: fetch!(attrs, :installation_ref),
         idempotency_key: fetch!(attrs, :idempotency_key),
         trace_ref: fetch!(attrs, :trace_ref),
         source_trace_ref: fetch!(attrs, :source_trace_ref),
         replay_trace_ref: fetch!(attrs, :replay_trace_ref),
         divergence_refs: divergence_refs,
         decision_class: decision,
         cost_class: cost_class,
         operator_action: fetch!(attrs, :operator_action),
         release_manifest_ref: fetch!(attrs, :release_manifest_ref)
       }}
    end
  end

  def replay_bundle(_attrs), do: {:error, :invalid_replay_bundle}

  defp reject_raw_payload(attrs) do
    case Enum.find(@raw_payload_keys, &Map.has_key?(attrs, &1)) do
      nil -> :ok
      key -> {:error, {:raw_replay_payload_forbidden, key}}
    end
  end

  defp required_strings(attrs, fields) do
    case Enum.find(fields, &(not present_string?(fetch(attrs, &1)))) do
      nil -> :ok
      field -> {:error, {:missing_replay_ref, field}}
    end
  end

  defp same_tenant_source(attrs) do
    tenant_ref = fetch(attrs, :tenant_ref)

    case fetch(attrs, :source_tenant_ref) do
      nil -> :ok
      source_tenant_ref when source_tenant_ref == tenant_ref -> :ok
      _tenant_ref -> {:error, :cross_tenant_replay_forbidden}
    end
  end

  defp member(attrs, field, allowed) do
    value = fetch(attrs, field)

    cond do
      value in allowed ->
        {:ok, value}

      is_binary(value) ->
        case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
          nil -> {:error, {:invalid_replay_field, field}}
          atom -> {:ok, atom}
        end

      true ->
        {:error, {:invalid_replay_field, field}}
    end
  end

  defp map_field(attrs, field, default) do
    case fetch(attrs, field, default) do
      value when is_map(value) -> {:ok, value}
      _value -> {:error, {:invalid_replay_field, field}}
    end
  end

  defp string_list_field(attrs, field, default) do
    values = fetch(attrs, field, default)

    if is_list(values) and Enum.all?(values, &present_string?/1) do
      {:ok, values}
    else
      {:error, {:invalid_replay_field, field}}
    end
  end

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false

  defp fetch!(attrs, field), do: fetch(attrs, field)
  defp fetch(attrs, field), do: fetch(attrs, field, nil)

  defp fetch(attrs, field, default),
    do: Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field)) || default
end
