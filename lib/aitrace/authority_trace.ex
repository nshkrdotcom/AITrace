defmodule AITrace.AuthorityTrace do
  @moduledoc """
  Ref-only authority trace event contracts.

  Authority trace events carry refs, redaction policy refs, overflow-safe
  actions, and proof artifact refs. They never carry provider payloads, raw
  credentials, native auth file contents, target credentials, or authorization
  headers.
  """

  alias AITrace.PersistencePosture

  @required_refs [
    :event_name,
    :authority_packet_ref,
    :system_authorization_ref,
    :provider_family,
    :provider_account_ref,
    :connector_instance_ref,
    :connector_binding_ref,
    :credential_handle_ref,
    :credential_lease_ref,
    :native_auth_assertion_ref,
    :target_ref,
    :attach_grant_ref,
    :operation_policy_ref,
    :requested_operation,
    :admission_state,
    :redaction_policy_ref,
    :proof_artifact_ref
  ]

  @forbidden_material [
    :api_key,
    :auth_json,
    :authorization_header,
    :native_auth_file,
    :private_key,
    :provider_payload,
    :raw_secret,
    :raw_token,
    :target_credentials,
    :token
  ]

  @provider_account_statuses [
    :known,
    :asserted,
    :unknown,
    :unavailable,
    :revoked,
    :rotated
  ]

  @identity_introspection_limits [
    :not_attempted,
    :ref_only,
    :redacted_summary,
    :unavailable
  ]

  @admission_states [
    :admitted,
    :pending,
    :rejected,
    :rejected_duplicate,
    :blocked
  ]

  @event_names [
    "authority.provider_dispatch",
    "authority.provider_rejection",
    "authority.provider_revocation",
    "authority.provider_retry",
    "authority.connector_admission",
    "authority.credential_materialization"
  ]

  @redaction_classes [
    "ref_only",
    "hash_ref",
    "redacted_summary",
    "spillover_ref"
  ]

  @event_fields @required_refs ++
                  [
                    :trace_ref,
                    :authority_decision_ref,
                    :rejection_reason,
                    :proof_refs,
                    :scanner_refs,
                    :redaction_class,
                    :provider_account_status,
                    :provider_account_evidence_ref,
                    :identity_introspection_limit,
                    :persistence_posture
                  ]
  @known_event_fields @event_fields ++ [:persistence_profile, :persistence_profile_ref]
  @overflow_safe_action "drop_raw_material_keep_ref"

  @enforce_keys @required_refs
  defstruct @required_refs ++
              [
                :trace_ref,
                :authority_decision_ref,
                :rejection_reason,
                proof_refs: [],
                scanner_refs: [],
                redaction_class: "ref_only",
                provider_account_status: :unknown,
                provider_account_evidence_ref: nil,
                identity_introspection_limit: :ref_only,
                persistence_posture: PersistencePosture.memory_ring(:authority_trace),
                raw_material_present?: false,
                overflow_safe_action: @overflow_safe_action,
                contract_version: "AITrace.AuthorityTraceEvent.v1"
              ]

  @type t :: %__MODULE__{
          event_name: String.t(),
          authority_packet_ref: String.t(),
          system_authorization_ref: String.t(),
          provider_family: String.t(),
          provider_account_ref: String.t(),
          connector_instance_ref: String.t(),
          credential_handle_ref: String.t(),
          credential_lease_ref: String.t(),
          native_auth_assertion_ref: String.t(),
          target_ref: String.t(),
          attach_grant_ref: String.t(),
          operation_policy_ref: String.t(),
          redaction_policy_ref: String.t(),
          proof_artifact_ref: String.t(),
          trace_ref: String.t() | nil,
          authority_decision_ref: String.t() | nil,
          provider_account_status: atom(),
          provider_account_evidence_ref: String.t() | nil,
          identity_introspection_limit: atom(),
          persistence_posture: PersistencePosture.t(),
          raw_material_present?: false,
          overflow_safe_action: String.t(),
          contract_version: String.t()
        }

  @spec provider_account_statuses() :: [atom()]
  def provider_account_statuses, do: @provider_account_statuses

  @spec identity_introspection_limits() :: [atom()]
  def identity_introspection_limits, do: @identity_introspection_limits

  @spec admission_states() :: [atom()]
  def admission_states, do: @admission_states

  @spec event_names() :: [String.t()]
  def event_names, do: @event_names

  @spec redaction_classes() :: [String.t()]
  def redaction_classes, do: @redaction_classes

  @spec event(map() | keyword()) ::
          {:ok, t()}
          | {:error, {:missing_required_refs, [atom()]}}
          | {:error, {:forbidden_trace_material, [atom()]}}
          | {:error, {:invalid_trace_enum, atom(), term(), [atom()]}}
          | {:error, {:invalid_trace_value, atom(), term(), [String.t()]}}
  def event(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    case forbidden_material_present(attrs) do
      [] ->
        with [] <- missing_required(attrs),
             {:ok, event_name} <-
               string_value(attrs, :event_name, @event_names, nil),
             {:ok, provider_account_status} <-
               enum_value(
                 attrs,
                 :provider_account_status,
                 @provider_account_statuses,
                 :unknown
               ),
             {:ok, identity_introspection_limit} <-
               enum_value(
                 attrs,
                 :identity_introspection_limit,
                 @identity_introspection_limits,
                 :ref_only
               ),
             {:ok, admission_state} <-
               enum_value(
                 attrs,
                 :admission_state,
                 @admission_states,
                 :pending
               ),
             {:ok, redaction_class} <-
               string_value(attrs, :redaction_class, @redaction_classes, "ref_only") do
          {:ok,
           build_event(
             attrs,
             event_name,
             provider_account_status,
             identity_introspection_limit,
             admission_state,
             redaction_class
           )}
        else
          missing when is_list(missing) -> {:error, {:missing_required_refs, missing}}
          {:error, reason} -> {:error, reason}
        end

      forbidden ->
        {:error, {:forbidden_trace_material, forbidden}}
    end
  end

  @spec event!(map() | keyword()) :: t()
  def event!(attrs) do
    case event(attrs) do
      {:ok, event} -> event
      {:error, reason} -> raise ArgumentError, "invalid authority trace event: #{inspect(reason)}"
    end
  end

  @spec export_attributes(t()) :: map()
  def export_attributes(%__MODULE__{} = event) do
    event
    |> Map.from_struct()
    |> Map.drop([:contract_version])
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp build_event(
         attrs,
         event_name,
         provider_account_status,
         identity_introspection_limit,
         admission_state,
         redaction_class
       ) do
    attrs =
      attrs
      |> Map.take(@event_fields)
      |> Map.put(:event_name, event_name)
      |> Map.put(:provider_account_status, provider_account_status)
      |> Map.put(:identity_introspection_limit, identity_introspection_limit)
      |> Map.put(:admission_state, admission_state)
      |> Map.put(:proof_refs, List.wrap(Map.get(attrs, :proof_refs, [])))
      |> Map.put(:scanner_refs, List.wrap(Map.get(attrs, :scanner_refs, [])))
      |> Map.put(:redaction_class, redaction_class)
      |> Map.put(:persistence_posture, PersistencePosture.resolve(:authority_trace, attrs))
      |> Map.put(:raw_material_present?, false)
      |> Map.put(:overflow_safe_action, @overflow_safe_action)
      |> Map.put(:contract_version, "AITrace.AuthorityTraceEvent.v1")

    struct!(__MODULE__, attrs)
  end

  defp missing_required(attrs) do
    Enum.reject(@required_refs, &present?(Map.get(attrs, &1)))
  end

  defp forbidden_material_present(attrs) do
    Enum.filter(@forbidden_material, &Map.has_key?(attrs, &1))
  end

  defp enum_value(attrs, field, allowed, default) do
    case Map.get(attrs, field, default) do
      value when is_atom(value) ->
        if value in allowed do
          {:ok, value}
        else
          {:error, {:invalid_trace_enum, field, value, allowed}}
        end

      value when is_binary(value) ->
        case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
          nil -> {:error, {:invalid_trace_enum, field, value, allowed}}
          atom -> {:ok, atom}
        end

      value ->
        {:error, {:invalid_trace_enum, field, value, allowed}}
    end
  end

  defp string_value(attrs, field, allowed, default) do
    case Map.get(attrs, field, default) do
      value when is_binary(value) ->
        if value in allowed do
          {:ok, value}
        else
          {:error, {:invalid_trace_value, field, value, allowed}}
        end

      value ->
        {:error, {:invalid_trace_value, field, value, allowed}}
    end
  end

  defp normalize(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize()

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    Enum.find(@known_event_fields ++ @forbidden_material, key, fn candidate ->
      Atom.to_string(candidate) == key
    end)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end
