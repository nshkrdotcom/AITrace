defmodule AITrace.Integrations.AgentTurn do
  @moduledoc """
  Bounded mapper from native agent turn events into AITrace evidence exports.

  This module accepts only refs, event kinds, ledger sequence numbers, and
  receipt refs. Raw prompts, raw lower payloads, and provider bodies are
  rejected before hashing or export receipt construction.
  """

  alias AITrace.ReplayContracts

  @event_kinds [:conversation, :execution, :projection, :evidence, :runtime_receipt]
  @raw_event_keys [
    :body,
    :payload,
    :provider_payload,
    :provider_response,
    :raw_body,
    :raw_payload,
    :raw_prompt,
    :secret,
    "body",
    "payload",
    "provider_payload",
    "provider_response",
    "raw_body",
    "raw_payload",
    "raw_prompt",
    "secret"
  ]

  @spec export_receipt(map()) :: {:ok, ReplayContracts.AgentEvidenceExport.t()} | {:error, term()}
  def export_receipt(attrs) when is_map(attrs) do
    with {:ok, ledger_ref} <- required_string(attrs, :ledger_ref),
         {:ok, trace_ref} <- required_string(attrs, :trace_ref),
         {:ok, authority_ref} <- required_string(attrs, :authority_ref),
         {:ok, runtime_receipt_refs} <-
           required_non_empty_string_list(attrs, :runtime_receipt_refs),
         {:ok, redaction_manifest_ref} <- required_string(attrs, :redaction_manifest_ref),
         {:ok, bounded_events} <- bounded_events(fetch(attrs, :events, [])),
         {:ok, from_seq, to_seq} <- sequence_range(bounded_events) do
      ReplayContracts.agent_evidence_export(%{
        export_ref: fetch(attrs, :export_ref) || export_ref(ledger_ref, from_seq, to_seq),
        trace_ref: trace_ref,
        ledger_ref: ledger_ref,
        runtime_receipt_refs: runtime_receipt_refs,
        authority_ref: authority_ref,
        export_profile: fetch(attrs, :export_profile, :redacted_replay),
        payload_hash: payload_hash(bounded_events),
        redaction_manifest_ref: redaction_manifest_ref,
        exported_at: fetch(attrs, :exported_at, DateTime.utc_now()),
        schema_ref: ReplayContracts.agent_export_schema_ref(),
        ledger_seq_from: from_seq,
        ledger_seq_to: to_seq,
        event_count: length(bounded_events),
        authoritative?: fetch(attrs, :authoritative?, false),
        durable_export_receipt_ref: fetch(attrs, :durable_export_receipt_ref)
      })
    end
  end

  def export_receipt(_attrs), do: {:error, :invalid_agent_turn_export}

  defp bounded_events(events) when is_list(events) do
    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      case bounded_event(event) do
        {:ok, bounded} -> {:cont, {:ok, [bounded | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, values |> Enum.reverse() |> Enum.sort_by(& &1.seq)}
      error -> error
    end
  end

  defp bounded_events(_events), do: {:error, {:invalid_agent_turn_export_field, :events}}

  defp bounded_event(event) when is_map(event) do
    with :ok <- reject_raw_event_payload(event),
         {:ok, seq} <- required_non_negative_integer(event, :seq),
         {:ok, event_ref} <- required_string(event, :event_ref),
         {:ok, event_kind} <- event_kind(event),
         {:ok, runtime_receipt_ref} <- optional_string(event, :runtime_receipt_ref) do
      {:ok,
       %{
         event_ref: event_ref,
         event_kind: event_kind,
         seq: seq,
         runtime_receipt_ref: runtime_receipt_ref
       }}
    end
  end

  defp bounded_event(_event), do: {:error, {:invalid_agent_turn_export_field, :events}}

  defp reject_raw_event_payload(event) do
    case Enum.find(@raw_event_keys, &Map.has_key?(event, &1)) do
      nil -> :ok
      key -> {:error, {:raw_agent_turn_event_payload_forbidden, key}}
    end
  end

  defp event_kind(event) do
    value = fetch(event, :event_kind)

    cond do
      value in @event_kinds ->
        {:ok, value}

      is_binary(value) ->
        case Enum.find(@event_kinds, &(Atom.to_string(&1) == value)) do
          nil -> {:error, {:invalid_agent_turn_export_field, :event_kind}}
          atom -> {:ok, atom}
        end

      true ->
        {:error, {:invalid_agent_turn_export_field, :event_kind}}
    end
  end

  defp sequence_range([]), do: {:error, {:missing_replay_ref, :events}}

  defp sequence_range([first | _rest] = events) do
    last = List.last(events)
    {:ok, first.seq, last.seq}
  end

  defp required_non_negative_integer(attrs, field) do
    case fetch(attrs, field) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _value -> {:error, {:invalid_agent_turn_export_field, field}}
    end
  end

  defp required_string(attrs, field) do
    case fetch(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_replay_ref, field}}
    end
  end

  defp optional_string(attrs, field) do
    case fetch(attrs, field) do
      nil -> {:ok, nil}
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:invalid_agent_turn_export_field, field}}
    end
  end

  defp required_non_empty_string_list(attrs, field) do
    case fetch(attrs, field) do
      [_value | _rest] = values ->
        if Enum.all?(values, &present_string?/1) do
          {:ok, values}
        else
          {:error, {:invalid_agent_turn_export_field, field}}
        end

      [] ->
        {:error, {:missing_replay_ref, field}}

      _value ->
        {:error, {:invalid_agent_turn_export_field, field}}
    end
  end

  defp payload_hash(bounded_events) do
    material =
      bounded_events
      |> inspect(limit: :infinity, printable_limit: :infinity)
      |> IO.iodata_to_binary()

    "sha256:" <> Base.encode16(:crypto.hash(:sha256, material), case: :lower)
  end

  defp export_ref(ledger_ref, from_seq, to_seq) do
    "agent-evidence-export://#{URI.encode_www_form(ledger_ref)}/#{from_seq}-#{to_seq}"
  end

  defp fetch(attrs, field), do: fetch(attrs, field, nil)

  defp fetch(attrs, field, default) do
    cond do
      Map.has_key?(attrs, field) -> Map.fetch!(attrs, field)
      Map.has_key?(attrs, Atom.to_string(field)) -> Map.fetch!(attrs, Atom.to_string(field))
      true -> default
    end
  end

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false
end
