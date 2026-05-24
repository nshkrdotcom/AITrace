defmodule AITrace.Trace.ReplayBundle do
  @moduledoc """
  Root AITrace replay bundle artifact for file exports.
  """

  alias AITrace.PersistencePosture

  @enforce_keys [
    :bundle_ref,
    :source_trace_ref,
    :replay_trace_ref,
    :divergence_list_ref,
    :audit_ref,
    :redaction_policy_ref,
    :release_manifest_ref
  ]
  defstruct @enforce_keys ++
              [
                :context_packet_ref,
                :context_packet_hash,
                :route_decision_ref,
                :model_invocation_ref,
                :model_receipt_ref,
                persistence_posture: PersistencePosture.memory_ring(:replay)
              ]

  @type t :: %__MODULE__{
          bundle_ref: String.t(),
          source_trace_ref: String.t(),
          replay_trace_ref: String.t(),
          divergence_list_ref: String.t(),
          audit_ref: String.t(),
          redaction_policy_ref: String.t(),
          release_manifest_ref: String.t(),
          context_packet_ref: String.t() | nil,
          context_packet_hash: String.t() | nil,
          route_decision_ref: String.t() | nil,
          model_invocation_ref: String.t() | nil,
          model_receipt_ref: String.t() | nil,
          persistence_posture: PersistencePosture.t()
        }

  @raw_keys [
    :body,
    :raw_body,
    :payload,
    :raw_payload,
    :prompt_body,
    :raw_prompt,
    :memory_body,
    :raw_memory_body,
    :provider_payload,
    :model_output,
    :provider_response,
    :eval_payload,
    :eval_output,
    :raw_eval,
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
    "model_output",
    "provider_response",
    "eval_payload",
    "eval_output",
    "raw_eval",
    "secret",
    "token"
  ]

  @required_fields [
    :bundle_ref,
    :source_trace_ref,
    :replay_trace_ref,
    :divergence_list_ref,
    :audit_ref,
    :redaction_policy_ref,
    :release_manifest_ref
  ]
  @optional_ref_fields [
    :context_packet_ref,
    :route_decision_ref,
    :model_invocation_ref,
    :model_receipt_ref
  ]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @required_fields),
         {:ok, optional_refs} <- optional_refs(attrs),
         {:ok, context_packet_hash} <- optional_sha256(attrs, :context_packet_hash) do
      {:ok,
       %__MODULE__{
         bundle_ref: fetch!(attrs, :bundle_ref),
         source_trace_ref: fetch!(attrs, :source_trace_ref),
         replay_trace_ref: fetch!(attrs, :replay_trace_ref),
         divergence_list_ref: fetch!(attrs, :divergence_list_ref),
         audit_ref: fetch!(attrs, :audit_ref),
         redaction_policy_ref: fetch!(attrs, :redaction_policy_ref),
         release_manifest_ref: fetch!(attrs, :release_manifest_ref),
         context_packet_ref: optional_refs[:context_packet_ref],
         context_packet_hash: context_packet_hash,
         route_decision_ref: optional_refs[:route_decision_ref],
         model_invocation_ref: optional_refs[:model_invocation_ref],
         model_receipt_ref: optional_refs[:model_receipt_ref],
         persistence_posture: PersistencePosture.resolve(:replay, attrs)
       }}
    end
  end

  def new(_attrs), do: {:error, :invalid_replay_bundle}

  defp reject_raw(attrs) do
    case Enum.find(@raw_keys, &Map.has_key?(attrs, &1)) do
      nil -> :ok
      key -> {:error, {:raw_replay_bundle_payload_forbidden, key}}
    end
  end

  defp required_strings(attrs, fields) do
    case Enum.find(fields, &(not present_string?(fetch(attrs, &1)))) do
      nil -> :ok
      field -> {:error, {:missing_replay_bundle_ref, field}}
    end
  end

  defp optional_refs(attrs) do
    Enum.reduce_while(@optional_ref_fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case optional_string(attrs, field) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp optional_string(attrs, field) do
    case fetch(attrs, field) do
      nil -> {:ok, nil}
      value when is_binary(value) -> optional_present_string(value, field)
      _value -> {:error, {:invalid_replay_bundle_ref, field}}
    end
  end

  defp optional_present_string(value, field) do
    if present_string?(value) do
      {:ok, value}
    else
      {:error, {:missing_replay_bundle_ref, field}}
    end
  end

  defp optional_sha256(attrs, field) do
    case fetch(attrs, field) do
      nil -> {:ok, nil}
      "sha256:" <> hash = value when byte_size(hash) == 64 -> {:ok, value}
      _value -> {:error, {:invalid_replay_bundle_ref, field}}
    end
  end

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false
  defp fetch!(attrs, field), do: fetch(attrs, field)
  defp fetch(attrs, field), do: Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))
end
