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
  defstruct @enforce_keys ++ [persistence_posture: PersistencePosture.memory_ring(:replay)]

  @type t :: %__MODULE__{
          bundle_ref: String.t(),
          source_trace_ref: String.t(),
          replay_trace_ref: String.t(),
          divergence_list_ref: String.t(),
          audit_ref: String.t(),
          redaction_policy_ref: String.t(),
          release_manifest_ref: String.t(),
          persistence_posture: PersistencePosture.t()
        }

  @raw_keys [
    :body,
    :raw_body,
    :payload,
    :raw_payload,
    :prompt_body,
    :model_output,
    :provider_response,
    :secret,
    :token,
    "body",
    "raw_body",
    "payload",
    "raw_payload",
    "prompt_body",
    "model_output",
    "provider_response",
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

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @required_fields) do
      {:ok,
       %__MODULE__{
         bundle_ref: fetch!(attrs, :bundle_ref),
         source_trace_ref: fetch!(attrs, :source_trace_ref),
         replay_trace_ref: fetch!(attrs, :replay_trace_ref),
         divergence_list_ref: fetch!(attrs, :divergence_list_ref),
         audit_ref: fetch!(attrs, :audit_ref),
         redaction_policy_ref: fetch!(attrs, :redaction_policy_ref),
         release_manifest_ref: fetch!(attrs, :release_manifest_ref),
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

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false
  defp fetch!(attrs, field), do: fetch(attrs, field)
  defp fetch(attrs, field), do: Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))
end
