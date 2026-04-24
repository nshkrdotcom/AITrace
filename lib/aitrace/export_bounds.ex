defmodule AITrace.ExportBounds do
  @moduledoc """
  Bounds trace export metadata and attributes before durable serialization.

  The file exporter is a generic trace sink, so it cannot know every upstream
  schema. This module applies a conservative exporter-local profile: only
  bounded JSON-safe fields with safe keys are kept inline, while raw payload
  shaped fields and oversize values are replaced with hashed spillover refs.
  """

  @schema_version "aitrace.export_bounds.v1"
  @max_attributes_per_map 32
  @max_key_bytes 64
  @max_value_bytes 512
  @max_collection_items 16
  @max_map_depth 2
  @redaction_policy_ref "aitrace.export_bounds.redact_hash.v1"
  @spillover_policy "aitrace.export_spillover.sha256_ref.v1"
  @overflow_safe_action "spill_to_artifact_ref"

  @blocked_field_fragments ~w(
    access_token
    api_token
    authorization
    credential
    password
    payload_body
    prompt_body
    prompt_content
    prompt_text
    provider_body
    provider_response
    raw_payload
    raw_prompt
    raw_provider
    raw_webhook
    refresh_token
    request_body
    response_body
    secret
    secret_token
    stderr
    stdout
    webhook_body
  )

  @safe_key_regex ~r/\A[A-Za-z0-9_.:-]{1,64}\z/

  @type surface :: :trace_metadata | :span_attributes | :event_attributes

  @spec profile() :: map()
  def profile do
    %{
      schema_version: @schema_version,
      trace_attribute_allowlist: "json_safe_keys_matching_[A-Za-z0-9_.:-]{1,64}",
      trace_attribute_blocklist: @blocked_field_fragments,
      max_attributes_per_map: @max_attributes_per_map,
      max_attribute_key_bytes: @max_key_bytes,
      max_attribute_value_bytes: @max_value_bytes,
      max_collection_items: @max_collection_items,
      max_map_depth: @max_map_depth,
      sample_policy: "always_keep_security",
      redaction_policy_ref: @redaction_policy_ref,
      hash_or_tokenize_fields: @blocked_field_fragments,
      spillover_artifact_policy: @spillover_policy,
      overflow_safe_action: @overflow_safe_action
    }
  end

  @spec bound_map!(map(), keyword()) :: map()
  def bound_map!(metadata, opts \\ []) when is_map(metadata) and is_list(opts) do
    surface = Keyword.get(opts, :surface, :trace_metadata)
    {bounded, overflow_refs} = bound_map(metadata, surface, 0)
    append_overflow_summary(bounded, surface, overflow_refs)
  end

  defp bound_map(metadata, surface, depth) do
    metadata
    |> Enum.reduce({%{}, []}, fn entry, {bounded, overflow_refs} ->
      entry_count = map_size(bounded)

      if entry_count >= @max_attributes_per_map do
        {bounded, [spill_ref(entry, surface, :attribute_count_exceeded) | overflow_refs]}
      else
        bound_entry(entry, bounded, overflow_refs, surface, depth)
      end
    end)
    |> then(fn {bounded, overflow_refs} -> {bounded, Enum.reverse(overflow_refs)} end)
  end

  defp bound_entry({key, value} = entry, bounded, overflow_refs, surface, depth) do
    key_string = to_string(key)

    cond do
      not safe_key?(key_string) ->
        {bounded, [spill_ref(entry, surface, :unsafe_key) | overflow_refs]}

      blocked_key?(key_string) ->
        {bounded, [spill_ref(entry, surface, :blocked_raw_field) | overflow_refs]}

      true ->
        case bound_value(value, surface, depth + 1) do
          {:inline, inline_value, value_overflow_refs} ->
            {Map.put(bounded, key_string, inline_value), value_overflow_refs ++ overflow_refs}

          {:spill, reason} ->
            {Map.put(bounded, key_string, spill_ref(value, surface, reason)), overflow_refs}
        end
    end
  end

  defp bound_value(value, _surface, _depth) when is_nil(value) or is_boolean(value),
    do: inline(value)

  defp bound_value(value, _surface, _depth) when is_integer(value) or is_float(value),
    do: inline(value)

  defp bound_value(value, _surface, _depth) when is_binary(value) do
    if byte_size(value) <= @max_value_bytes do
      inline(value)
    else
      {:spill, :value_bytes_exceeded}
    end
  end

  defp bound_value(value, _surface, _depth) when is_atom(value), do: inline(Atom.to_string(value))

  defp bound_value(%DateTime{} = value, _surface, _depth), do: inline(DateTime.to_iso8601(value))

  defp bound_value(value, surface, depth) when is_list(value) do
    if length(value) > @max_collection_items do
      {:spill, :collection_items_exceeded}
    else
      {items, overflow_refs} =
        value
        |> Enum.map(&bound_value(&1, surface, depth + 1))
        |> Enum.reduce({[], []}, fn
          {:inline, inline_value, item_refs}, {items, refs} ->
            {[inline_value | items], item_refs ++ refs}

          {:spill, reason}, {items, refs} ->
            {[spill_ref(value, surface, reason) | items], refs}
        end)

      {:inline, Enum.reverse(items), overflow_refs}
    end
  end

  defp bound_value(value, surface, depth) when is_map(value) do
    cond do
      depth > @max_map_depth ->
        {:spill, :map_depth_exceeded}

      map_size(value) > @max_collection_items ->
        {:spill, :collection_items_exceeded}

      true ->
        {bounded, overflow_refs} = bound_map(value, surface, depth)
        {:inline, bounded, overflow_refs}
    end
  end

  defp bound_value(_value, _surface, _depth), do: {:spill, :unsupported_value}

  defp inline(value), do: {:inline, value, []}

  defp append_overflow_summary(bounded, _surface, []), do: bounded

  defp append_overflow_summary(bounded, surface, overflow_refs) do
    Map.put(bounded, "_aitrace_export_overflow", %{
      "schema_version" => @schema_version,
      "surface" => Atom.to_string(surface),
      "overflow_safe_action" => @overflow_safe_action,
      "redaction_policy_ref" => @redaction_policy_ref,
      "spillover_artifact_policy" => @spillover_policy,
      "count" => length(overflow_refs),
      "refs" => overflow_refs
    })
  end

  defp safe_key?(key), do: byte_size(key) <= @max_key_bytes and Regex.match?(@safe_key_regex, key)

  defp blocked_key?(key) do
    normalized = String.downcase(key)
    normalized == "raw" or Enum.any?(@blocked_field_fragments, &String.contains?(normalized, &1))
  end

  defp spill_ref(value, surface, reason) do
    encoded = canonical_encode(value)
    sha256 = sha256(encoded)

    %{
      "ref" => "aitrace://export-spillover/#{sha256}",
      "hash_algorithm" => "sha256",
      "sha256" => sha256,
      "surface" => Atom.to_string(surface),
      "original_bytes" => byte_size(encoded),
      "reason" => Atom.to_string(reason),
      "redaction_policy_ref" => @redaction_policy_ref,
      "spillover_artifact_policy" => @spillover_policy,
      "overflow_safe_action" => @overflow_safe_action
    }
  end

  defp canonical_encode(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> encoded
      {:error, _reason} -> :erlang.term_to_binary(value)
    end
  end

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
