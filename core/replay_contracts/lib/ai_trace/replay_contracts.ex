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
  @trace_profiles [:production_default, :stacklab_proof]
  @agent_export_schema_ref "schema://aitrace/agent-evidence-export/v1"
  @agent_export_profiles [:summary, :redacted_replay, :full_local_debug]
  @lineage_event_kinds [
    :semantic_intent,
    :semantic_normalized,
    :command_recorded,
    :authority_compiled,
    :workflow_started,
    :operation_requested,
    :jido_manifest_resolved,
    :credential_lease_materialized,
    :effect_requested,
    :effect_receipted,
    :receipt_reduced,
    :evidence_attached,
    :review_opened,
    :review_skipped,
    :projection_updated,
    :replay_exported,
    :retry_scheduled,
    :operation_failed,
    :operation_canceled
  ]
  @trace_levels [:core_lineage, :detailed_proof, :replay_minimum]
  @emission_modes [:inline, :async, :batched]
  @stacklab_proof_required_event_kinds [
    :operation_requested,
    :effect_requested,
    :effect_receipted,
    :receipt_reduced,
    :projection_updated
  ]
  @merge_semantics [
    :diagnostic,
    :set_union,
    :map_merge_by_key,
    :max,
    :min,
    :last_write_by_causal_order,
    :append_by_projection_order,
    :state_transition
  ]

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
  @lineage_event_required [
    :event_ref,
    :trace_ref,
    :event_kind,
    :occurred_at,
    :causal_order,
    :merge_semantics,
    :trace_level
  ]
  @agent_export_required [
    :export_ref,
    :trace_ref,
    :ledger_ref,
    :authority_ref,
    :payload_hash,
    :redaction_manifest_ref,
    :schema_ref
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

  defmodule LineageReplayEvent do
    @moduledoc "Ref-only execution lineage event used for causal replay proofs."
    @enforce_keys [
      :event_ref,
      :trace_ref,
      :event_kind,
      :occurred_at,
      :predecessor_event_refs,
      :root_event?,
      :projection_key,
      :projection_visible?,
      :projection_order_key,
      :causal_order,
      :merge_semantics,
      :trace_level,
      :metadata_refs
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            event_ref: String.t(),
            trace_ref: String.t(),
            event_kind: atom(),
            occurred_at: integer(),
            predecessor_event_refs: [String.t()],
            root_event?: boolean(),
            projection_key: String.t() | nil,
            projection_visible?: boolean(),
            projection_order_key: String.t(),
            causal_order: integer(),
            merge_semantics: atom(),
            trace_level: atom(),
            metadata_refs: map()
          }
  end

  defmodule TraceLevelPolicy do
    @moduledoc "Trace-level requirements for production and StackLab proof runs."
    @enforce_keys [
      :profile,
      :default_trace_level,
      :required_trace_level,
      :allowed_trace_levels,
      :required_event_kinds,
      :requires_detailed_proof?,
      :production_default?
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            profile: atom(),
            default_trace_level: atom(),
            required_trace_level: atom(),
            allowed_trace_levels: [atom()],
            required_event_kinds: [atom()],
            requires_detailed_proof?: boolean(),
            production_default?: boolean()
          }
  end

  defmodule AgentEvidenceExport do
    @moduledoc "Bounded agent evidence export receipt tied to ledger and runtime receipts."
    @enforce_keys [
      :export_ref,
      :trace_ref,
      :ledger_ref,
      :runtime_receipt_refs,
      :authority_ref,
      :export_profile,
      :payload_hash,
      :redaction_manifest_ref,
      :exported_at,
      :schema_ref,
      :ledger_seq_from,
      :ledger_seq_to,
      :event_count,
      :authoritative?
    ]
    defstruct @enforce_keys ++ [durable_export_receipt_ref: nil]

    @type t :: %__MODULE__{
            export_ref: String.t(),
            trace_ref: String.t(),
            ledger_ref: String.t(),
            runtime_receipt_refs: [String.t()],
            authority_ref: String.t(),
            export_profile: atom(),
            payload_hash: String.t(),
            redaction_manifest_ref: String.t(),
            exported_at: DateTime.t(),
            schema_ref: String.t(),
            ledger_seq_from: non_neg_integer(),
            ledger_seq_to: non_neg_integer(),
            event_count: pos_integer(),
            authoritative?: boolean(),
            durable_export_receipt_ref: String.t() | nil
          }
  end

  @spec replay_modes() :: [atom()]
  def replay_modes, do: @replay_modes

  @spec side_effect_policies() :: [atom()]
  def side_effect_policies, do: @side_effect_policies

  @spec divergence_phases() :: [atom()]
  def divergence_phases, do: @divergence_phases

  @spec lineage_event_kinds() :: [atom()]
  def lineage_event_kinds, do: @lineage_event_kinds

  @spec trace_levels() :: [atom()]
  def trace_levels, do: @trace_levels

  @spec trace_profiles() :: [atom()]
  def trace_profiles, do: @trace_profiles

  @spec agent_export_schema_ref() :: String.t()
  def agent_export_schema_ref, do: @agent_export_schema_ref

  @spec agent_export_profiles() :: [atom()]
  def agent_export_profiles, do: @agent_export_profiles

  @spec emission_modes() :: [atom()]
  def emission_modes, do: @emission_modes

  @spec merge_semantics() :: [atom()]
  def merge_semantics, do: @merge_semantics

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

  @spec agent_evidence_export(map() | AgentEvidenceExport.t()) ::
          {:ok, AgentEvidenceExport.t()} | {:error, term()}
  def agent_evidence_export(%AgentEvidenceExport{} = export), do: {:ok, export}

  def agent_evidence_export(attrs) when is_map(attrs) do
    with :ok <- reject_raw_payload(attrs),
         :ok <- required_strings(attrs, @agent_export_required),
         :ok <- expected_schema(attrs),
         {:ok, export_profile} <- member(attrs, :export_profile, @agent_export_profiles),
         {:ok, runtime_receipt_refs} <-
           non_empty_string_list_field(attrs, :runtime_receipt_refs),
         {:ok, ledger_seq_from} <- non_negative_integer_field(attrs, :ledger_seq_from),
         {:ok, ledger_seq_to} <- non_negative_integer_field(attrs, :ledger_seq_to),
         {:ok, event_count} <- positive_integer_field(attrs, :event_count),
         :ok <- sequence_complete(ledger_seq_from, ledger_seq_to, event_count),
         {:ok, exported_at} <- datetime_field(attrs, :exported_at),
         {:ok, authoritative?} <- boolean_field(attrs, :authoritative?, false),
         {:ok, durable_export_receipt_ref} <-
           durable_export_receipt_ref(attrs, authoritative?),
         :ok <- payload_hash(fetch!(attrs, :payload_hash)) do
      {:ok,
       %AgentEvidenceExport{
         export_ref: fetch!(attrs, :export_ref),
         trace_ref: fetch!(attrs, :trace_ref),
         ledger_ref: fetch!(attrs, :ledger_ref),
         runtime_receipt_refs: runtime_receipt_refs,
         authority_ref: fetch!(attrs, :authority_ref),
         export_profile: export_profile,
         payload_hash: fetch!(attrs, :payload_hash),
         redaction_manifest_ref: fetch!(attrs, :redaction_manifest_ref),
         exported_at: exported_at,
         schema_ref: fetch!(attrs, :schema_ref),
         ledger_seq_from: ledger_seq_from,
         ledger_seq_to: ledger_seq_to,
         event_count: event_count,
         authoritative?: authoritative?,
         durable_export_receipt_ref: durable_export_receipt_ref
       }}
    end
  end

  def agent_evidence_export(_attrs), do: {:error, :invalid_agent_evidence_export}

  @spec trace_level_policy(atom() | String.t()) ::
          {:ok, TraceLevelPolicy.t()} | {:error, term()}
  def trace_level_policy(:production_default) do
    {:ok,
     %TraceLevelPolicy{
       profile: :production_default,
       default_trace_level: :core_lineage,
       required_trace_level: :core_lineage,
       allowed_trace_levels: [:core_lineage, :replay_minimum],
       required_event_kinds: [],
       requires_detailed_proof?: false,
       production_default?: true
     }}
  end

  def trace_level_policy(:stacklab_proof) do
    {:ok,
     %TraceLevelPolicy{
       profile: :stacklab_proof,
       default_trace_level: :detailed_proof,
       required_trace_level: :detailed_proof,
       allowed_trace_levels: @trace_levels,
       required_event_kinds: @stacklab_proof_required_event_kinds,
       requires_detailed_proof?: true,
       production_default?: false
     }}
  end

  def trace_level_policy(profile) when is_binary(profile) do
    case Enum.find(@trace_profiles, &(Atom.to_string(&1) == profile)) do
      nil -> {:error, {:invalid_replay_field, :trace_profile}}
      atom -> trace_level_policy(atom)
    end
  end

  def trace_level_policy(_profile), do: {:error, {:invalid_replay_field, :trace_profile}}

  @spec lineage_replay_event(map() | LineageReplayEvent.t()) ::
          {:ok, LineageReplayEvent.t()} | {:error, term()}
  def lineage_replay_event(%LineageReplayEvent{} = event), do: {:ok, event}

  def lineage_replay_event(attrs) when is_map(attrs) do
    with :ok <- reject_raw_payload(attrs),
         :ok <-
           required_strings(
             attrs,
             @lineage_event_required --
               [:event_kind, :occurred_at, :causal_order, :merge_semantics, :trace_level]
           ),
         {:ok, event_kind} <- member(attrs, :event_kind, @lineage_event_kinds),
         {:ok, merge_semantics} <- member(attrs, :merge_semantics, @merge_semantics),
         {:ok, trace_level} <- member(attrs, :trace_level, @trace_levels),
         {:ok, occurred_at} <- integer_field(attrs, :occurred_at),
         {:ok, causal_order} <- integer_field(attrs, :causal_order),
         {:ok, predecessor_event_refs} <- string_list_field(attrs, :predecessor_event_refs, []),
         {:ok, root_event?} <- boolean_field(attrs, :root_event?, false),
         {:ok, projection_visible?} <- boolean_field(attrs, :projection_visible?, false),
         {:ok, projection_key} <- projection_key(attrs, projection_visible?),
         {:ok, projection_order_key} <-
           optional_string(attrs, :projection_order_key, fetch!(attrs, :event_ref)),
         {:ok, metadata_refs} <- map_field(attrs, :metadata_refs, %{}),
         :ok <- lineage_metadata_contract(metadata_refs),
         :ok <- predecessor_contract(root_event?, predecessor_event_refs) do
      {:ok,
       %LineageReplayEvent{
         event_ref: fetch!(attrs, :event_ref),
         trace_ref: fetch!(attrs, :trace_ref),
         event_kind: event_kind,
         occurred_at: occurred_at,
         predecessor_event_refs: predecessor_event_refs,
         root_event?: root_event?,
         projection_key: projection_key,
         projection_visible?: projection_visible?,
         projection_order_key: projection_order_key,
         causal_order: causal_order,
         merge_semantics: merge_semantics,
         trace_level: trace_level,
         metadata_refs: metadata_refs
       }}
    end
  end

  def lineage_replay_event(_attrs), do: {:error, :invalid_lineage_replay_event}

  @spec lineage_replay_events([map() | LineageReplayEvent.t()]) ::
          {:ok, [LineageReplayEvent.t()]} | {:error, term()}
  def lineage_replay_events(events) when is_list(events) do
    Enum.reduce_while(events, {:ok, []}, fn attrs, {:ok, acc} ->
      case lineage_replay_event(attrs) do
        {:ok, event} -> {:cont, {:ok, [event | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  def lineage_replay_events(_events), do: {:error, :invalid_lineage_replay_events}

  defp expected_schema(attrs) do
    case fetch(attrs, :schema_ref) do
      @agent_export_schema_ref -> :ok
      schema_ref -> {:error, {:schema_mismatch, schema_ref}}
    end
  end

  defp sequence_complete(from_seq, to_seq, event_count) when to_seq >= from_seq do
    if to_seq - from_seq + 1 == event_count do
      :ok
    else
      {:error,
       {:missing_replay_sequence, %{from_seq: from_seq, to_seq: to_seq, event_count: event_count}}}
    end
  end

  defp sequence_complete(from_seq, to_seq, event_count) do
    {:error,
     {:missing_replay_sequence, %{from_seq: from_seq, to_seq: to_seq, event_count: event_count}}}
  end

  defp payload_hash("sha256:" <> hash) when byte_size(hash) == 64, do: :ok
  defp payload_hash(_value), do: {:error, {:invalid_replay_field, :payload_hash}}

  defp durable_export_receipt_ref(attrs, true) do
    case fetch(attrs, :durable_export_receipt_ref) do
      value when is_binary(value) ->
        if present_string?(value) do
          {:ok, value}
        else
          {:error, {:missing_replay_ref, :durable_export_receipt_ref}}
        end

      _value ->
        {:error, {:missing_replay_ref, :durable_export_receipt_ref}}
    end
  end

  defp durable_export_receipt_ref(attrs, false) do
    case fetch(attrs, :durable_export_receipt_ref) do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, value}
      _value -> {:error, {:invalid_replay_field, :durable_export_receipt_ref}}
    end
  end

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

  defp lineage_metadata_contract(metadata_refs) do
    with :ok <- optional_metadata_string(metadata_refs, :retention_policy_ref),
         :ok <- optional_metadata_positive_integer(metadata_refs, :ttl_seconds),
         {:ok, emission_mode} <-
           optional_metadata_member(metadata_refs, :emission_mode, @emission_modes),
         :ok <- optional_metadata_string(metadata_refs, :emission_expectation_ref) do
      batch_emission_contract(metadata_refs, emission_mode)
    end
  end

  defp optional_metadata_string(metadata_refs, field) do
    case fetch(metadata_refs, field) do
      nil -> :ok
      value when is_binary(value) -> nonempty_metadata_string(field, value)
      _value -> {:error, {:invalid_replay_field, field}}
    end
  end

  defp required_metadata_string(metadata_refs, field) do
    case fetch(metadata_refs, field) do
      nil -> {:error, {:missing_replay_ref, field}}
      value when is_binary(value) -> nonempty_metadata_string(field, value)
      _value -> {:error, {:invalid_replay_field, field}}
    end
  end

  defp nonempty_metadata_string(field, value) do
    if present_string?(value) do
      :ok
    else
      {:error, {:missing_replay_ref, field}}
    end
  end

  defp optional_metadata_positive_integer(metadata_refs, field) do
    case fetch(metadata_refs, field) do
      nil -> :ok
      value when is_integer(value) and value > 0 -> :ok
      _value -> {:error, {:invalid_replay_field, field}}
    end
  end

  defp optional_metadata_member(metadata_refs, field, allowed) do
    case fetch(metadata_refs, field) do
      nil -> {:ok, nil}
      value when is_atom(value) -> metadata_atom_member(value, field, allowed)
      value when is_binary(value) -> metadata_binary_member(value, field, allowed)
      _value -> {:error, {:invalid_replay_field, field}}
    end
  end

  defp metadata_atom_member(value, field, allowed) do
    if value in allowed do
      {:ok, value}
    else
      {:error, {:invalid_replay_field, field}}
    end
  end

  defp metadata_binary_member(value, field, allowed) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> {:error, {:invalid_replay_field, field}}
      atom -> {:ok, atom}
    end
  end

  defp batch_emission_contract(metadata_refs, :batched),
    do: required_metadata_string(metadata_refs, :batch_ref)

  defp batch_emission_contract(_metadata_refs, _emission_mode), do: :ok

  defp integer_field(attrs, field) do
    case fetch(attrs, field) do
      value when is_integer(value) -> {:ok, value}
      _value -> {:error, {:invalid_replay_field, field}}
    end
  end

  defp non_negative_integer_field(attrs, field) do
    case fetch(attrs, field) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _value -> {:error, {:invalid_replay_field, field}}
    end
  end

  defp positive_integer_field(attrs, field) do
    case fetch(attrs, field) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> {:error, {:invalid_replay_field, field}}
    end
  end

  defp datetime_field(attrs, field) do
    case fetch(attrs, field) do
      %DateTime{} = value ->
        {:ok, value}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          {:error, _reason} -> {:error, {:invalid_replay_field, field}}
        end

      _value ->
        {:error, {:invalid_replay_field, field}}
    end
  end

  defp boolean_field(attrs, field, default) do
    case fetch(attrs, field, default) do
      value when is_boolean(value) -> {:ok, value}
      _value -> {:error, {:invalid_replay_field, field}}
    end
  end

  defp optional_string(attrs, field, default) do
    case fetch(attrs, field, default) do
      nil ->
        {:error, {:missing_replay_ref, field}}

      value when is_binary(value) ->
        if present_string?(value) do
          {:ok, value}
        else
          {:error, {:missing_replay_ref, field}}
        end

      _value ->
        {:error, {:invalid_replay_field, field}}
    end
  end

  defp projection_key(attrs, false) do
    case fetch(attrs, :projection_key) do
      nil -> {:ok, nil}
      value when is_binary(value) -> optional_string(attrs, :projection_key, value)
      _value -> {:error, {:invalid_replay_field, :projection_key}}
    end
  end

  defp projection_key(attrs, true), do: optional_string(attrs, :projection_key, nil)

  defp predecessor_contract(true, []), do: :ok
  defp predecessor_contract(false, [_predecessor | _rest]), do: :ok

  defp predecessor_contract(true, _predecessors),
    do: {:error, {:invalid_replay_field, :root_event?}}

  defp predecessor_contract(false, []),
    do: {:error, {:missing_replay_ref, :predecessor_event_refs}}

  defp string_list_field(attrs, field, default) do
    values = fetch(attrs, field, default)

    if is_list(values) and Enum.all?(values, &present_string?/1) do
      {:ok, values}
    else
      {:error, {:invalid_replay_field, field}}
    end
  end

  defp non_empty_string_list_field(attrs, field) do
    case string_list_field(attrs, field, []) do
      {:ok, [_value | _rest] = values} -> {:ok, values}
      {:ok, []} -> {:error, {:missing_replay_ref, field}}
      error -> error
    end
  end

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false

  defp fetch!(attrs, field), do: fetch(attrs, field)
  defp fetch(attrs, field), do: fetch(attrs, field, nil)

  defp fetch(attrs, field, default),
    do: Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field)) || default
end
