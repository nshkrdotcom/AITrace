defmodule AITrace.ExportBounds do
  @moduledoc """
  Bounds trace export metadata and attributes before durable serialization.

  The file exporter is a generic trace sink, so it cannot know every upstream
  schema. This module applies a conservative exporter-local profile: only
  bounded JSON-safe fields with safe keys are kept inline, while raw payload
  shaped fields and oversize values are replaced with hashed spillover refs.
  """

  alias GroundPlane.Boundary.Codec, as: BoundaryCodec

  @schema_version "aitrace.export_bounds.v1"
  @max_attributes_per_map 32
  @max_key_bytes 64
  @max_value_bytes 512
  @max_collection_items 16
  @max_map_depth 2
  @redaction_policy_ref "aitrace.export_bounds.redact_hash.v1"
  @spillover_policy "aitrace.export_spillover.sha256_ref.v1"
  @overflow_safe_action "spill_to_artifact_ref"
  @boundary_sensitive_keys ~w(
    access_token
    api_key
    client_secret
    credential_material
    material
    private_key
    raw_credential
    refresh_token
    secret
    token
    webhook_secret
  )

  @blocked_field_fragments ~w(
    access_token
    api_token
    authorization
    budget_amount
    cost_amount
    credential
    guard_payload
    guard_violation_body
    guard_violation_payload
    memory_body
    memory_content
    password
    payload_body
    prompt_body
    prompt_content
    prompt_text
    provider_body
    provider_response
    replay_divergence_excerpt
    raw_memory
    raw_guard
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

  @type surface :: :trace_metadata | :span_attributes | :event_attributes

  @spec profile() :: map()
  def profile do
    %{
      schema_version: @schema_version,
      trace_attribute_allowlist: "json_safe_ascii_key_chars_1_to_64",
      trace_attribute_blocklist: @blocked_field_fragments,
      max_attributes_per_map: @max_attributes_per_map,
      max_attribute_key_bytes: @max_key_bytes,
      max_attribute_value_bytes: @max_value_bytes,
      max_collection_items: @max_collection_items,
      max_map_depth: @max_map_depth,
      sample_policy: "always_keep_security",
      default_capture_level_ref: "capture-level://redacted-memory-ring",
      optional_capture_off_ref: "capture-level://off",
      redaction_policy_ref: @redaction_policy_ref,
      hash_or_tokenize_fields: @blocked_field_fragments,
      spillover_artifact_policy: @spillover_policy,
      overflow_safe_action: @overflow_safe_action
    }
  end

  @spec capture_profile(:off | :memory_ring | :redacted_debug | :durable_redacted) :: map()
  def capture_profile(:off) do
    %{
      capture_level_ref: "capture-level://off",
      retained?: false,
      raw_payload_persistence?: false,
      overflow_safe_action: "drop_without_mutating_provider_effect"
    }
  end

  def capture_profile(:memory_ring) do
    %{
      capture_level_ref: "capture-level://redacted-memory-ring",
      retained?: true,
      raw_payload_persistence?: false,
      overflow_safe_action: @overflow_safe_action
    }
  end

  def capture_profile(:redacted_debug) do
    %{
      capture_level_ref: "capture-level://redacted-debug",
      retained?: true,
      raw_payload_persistence?: false,
      overflow_safe_action: @overflow_safe_action
    }
  end

  def capture_profile(:durable_redacted) do
    %{
      capture_level_ref: "capture-level://redacted-summary",
      retained?: true,
      raw_payload_persistence?: false,
      overflow_safe_action: @overflow_safe_action
    }
  end

  @spec memory_body_class() :: map()
  def memory_body_class do
    %{
      class_ref: "aitrace.redaction.memory_body.v1",
      redaction_policy_ref: @redaction_policy_ref,
      safe_action: "hash_ref_or_redacted_excerpt_only",
      blocked_field_fragments: ["memory_body", "memory_content", "raw_memory"]
    }
  end

  @spec budget_amount_class() :: map()
  def budget_amount_class do
    %{
      class_ref: "aitrace.redaction.budget_amount.v1",
      redaction_policy_ref: @redaction_policy_ref,
      safe_action: "redact_amounts_above_export_threshold",
      blocked_field_fragments: ["budget_amount", "cost_amount"]
    }
  end

  @spec cost_amount_floor_class() :: map()
  def cost_amount_floor_class do
    %{
      class_ref: "aitrace.redaction.cost_amount_floor.v1",
      redaction_policy_ref: @redaction_policy_ref,
      safe_action: "redact_provider_amounts_below_floor_to_class",
      blocked_field_fragments: ["cost_amount", "amount_native", "raw_amount"]
    }
  end

  @spec cost_amount_ceiling_class() :: map()
  def cost_amount_ceiling_class do
    %{
      class_ref: "aitrace.redaction.cost_amount_ceiling.v1",
      redaction_policy_ref: @redaction_policy_ref,
      safe_action: "hash_provider_amounts_above_ceiling_to_ref",
      blocked_field_fragments: ["cost_amount", "amount_native", "raw_amount"]
    }
  end

  @spec prompt_body_class() :: map()
  def prompt_body_class do
    %{
      class_ref: "aitrace.redaction.prompt_body.v1",
      redaction_policy_ref: @redaction_policy_ref,
      safe_action: "always_redact_prompt_body_to_hash_ref",
      blocked_field_fragments: ["prompt_body", "prompt_content", "prompt_text", "raw_prompt"]
    }
  end

  @spec guard_violation_excerpt_class() :: map()
  def guard_violation_excerpt_class do
    %{
      class_ref: "aitrace.redaction.guard_violation_excerpt.v1",
      redaction_policy_ref: @redaction_policy_ref,
      safe_action: "bounded_excerpt_only_never_raw_payload",
      blocked_field_fragments: [
        "guard_payload",
        "guard_violation_body",
        "guard_violation_payload",
        "raw_guard"
      ]
    }
  end

  @spec replay_divergence_excerpt_class() :: map()
  def replay_divergence_excerpt_class do
    %{
      class_ref: "aitrace.redaction.replay_divergence_excerpt.v1",
      redaction_policy_ref: @redaction_policy_ref,
      safe_action: "bounded_or_hash_ref_only",
      blocked_field_fragments: [
        "model_output",
        "provider_response",
        "raw_output",
        "replay_divergence_excerpt"
      ]
    }
  end

  @spec bound_map!(map(), keyword()) :: map()
  def bound_map!(metadata, opts \\ []) when is_map(metadata) and is_list(opts) do
    surface = Keyword.get(opts, :surface, :trace_metadata)
    {bounded, overflow_refs} = bound_map(metadata, surface, 0)
    append_overflow_summary(bounded, surface, overflow_refs)
  end

  @doc """
  Redacts sensitive fields while preserving their keys as GAOP tombstones.
  """
  @spec tombstone_map!(map(), keyword()) :: map()
  def tombstone_map!(metadata, opts \\ []) when is_map(metadata) and is_list(opts) do
    max_depth = Keyword.get(opts, :max_depth, @max_map_depth + 2)
    tombstone_map(metadata, 0, max_depth)
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

  defp safe_key?(key) do
    byte_size(key) in 1..@max_key_bytes and
      key
      |> :binary.bin_to_list()
      |> Enum.all?(&safe_key_byte?/1)
  end

  defp safe_key_byte?(byte)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in [?_, ?., ?:, ?-],
       do: true

  defp safe_key_byte?(_byte), do: false

  defp blocked_key?(key) do
    normalized = String.downcase(key)

    normalized == "raw" or normalized in @boundary_sensitive_keys or
      Enum.any?(@blocked_field_fragments, &String.contains?(normalized, &1))
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

  defp tombstone_map(metadata, depth, max_depth) do
    metadata
    |> Enum.map(fn {key, value} ->
      key_string = to_string(key)

      cond do
        blocked_key?(key_string) ->
          {key_string, tombstone(value)}

        is_map(value) and depth < max_depth ->
          {key_string, tombstone_map(value, depth + 1, max_depth)}

        is_list(value) and depth < max_depth ->
          {key_string, Enum.map(value, &tombstone_list_value(&1, depth + 1, max_depth))}

        is_atom(value) ->
          {key_string, Atom.to_string(value)}

        true ->
          {key_string, value}
      end
    end)
    |> Map.new()
  end

  defp tombstone_list_value(value, depth, max_depth) when is_map(value) and depth < max_depth do
    tombstone_map(value, depth + 1, max_depth)
  end

  defp tombstone_list_value(value, _depth, _max_depth) when is_atom(value),
    do: Atom.to_string(value)

  defp tombstone_list_value(value, _depth, _max_depth), do: value

  defp tombstone(value) do
    "[REDACTED: sha256:" <> sha256(tombstone_encode(value)) <> "]"
  end

  defp tombstone_encode(value) do
    value
    |> tombstone_hash_shape()
    |> BoundaryCodec.encode!()
  end

  defp canonical_encode(value) do
    value
    |> spill_hash_shape()
    |> BoundaryCodec.encode!()
  end

  defp spill_hash_shape(nil), do: %{"type" => "nil"}

  defp spill_hash_shape(value) when is_boolean(value),
    do: %{"type" => "boolean", "value" => value}

  defp spill_hash_shape(value) when is_integer(value),
    do: %{"type" => "integer", "value" => value}

  defp spill_hash_shape(value) when is_float(value),
    do: %{"type" => "float", "text" => :erlang.float_to_binary(value, [:short])}

  defp spill_hash_shape(value) when is_binary(value),
    do: %{"type" => "binary", "byte_size" => byte_size(value)}

  defp spill_hash_shape(value) when is_atom(value),
    do: %{"type" => "atom", "text" => Atom.to_string(value)}

  defp spill_hash_shape(%DateTime{} = value),
    do: %{"type" => "datetime", "text" => DateTime.to_iso8601(value)}

  defp spill_hash_shape(value) when is_list(value) do
    %{
      "type" => "list",
      "length" => length(value),
      "items" => Enum.map(Enum.take(value, @max_collection_items), &spill_hash_shape/1)
    }
  end

  defp spill_hash_shape(value) when is_tuple(value) do
    items =
      value
      |> Tuple.to_list()
      |> Enum.map(&spill_hash_shape/1)

    %{"type" => "tuple", "tuple_size" => tuple_size(value), "items" => items}
  end

  defp spill_hash_shape(%_struct{} = value),
    do: %{"type" => "struct", "module" => value.__struct__ |> Module.split() |> Enum.join(".")}

  defp spill_hash_shape(value) when is_map(value) do
    safe_entries =
      value
      |> Enum.map(fn {key, nested_value} ->
        {to_string(key), spill_hash_shape(nested_value)}
      end)
      |> Enum.reject(fn {key, _nested_value} ->
        blocked_key?(key) or key in @boundary_sensitive_keys
      end)
      |> Enum.take(@max_collection_items)
      |> Map.new()

    %{
      "type" => "map",
      "entry_count" => map_size(value),
      "safe_entries" => safe_entries
    }
  end

  defp spill_hash_shape(value) when is_pid(value), do: %{"type" => "pid"}
  defp spill_hash_shape(value) when is_reference(value), do: %{"type" => "reference"}
  defp spill_hash_shape(value) when is_port(value), do: %{"type" => "port"}
  defp spill_hash_shape(value) when is_function(value), do: %{"type" => "function"}

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp tombstone_hash_shape(nil), do: %{"type" => "nil"}

  defp tombstone_hash_shape(value) when is_boolean(value),
    do: %{"type" => "boolean", "value" => value}

  defp tombstone_hash_shape(value) when is_integer(value),
    do: %{"type" => "integer", "value" => value}

  defp tombstone_hash_shape(value) when is_float(value),
    do: %{"type" => "float", "text" => :erlang.float_to_binary(value, [:short])}

  defp tombstone_hash_shape(value) when is_binary(value),
    do: %{"type" => "binary", "value" => value}

  defp tombstone_hash_shape(value) when is_atom(value),
    do: %{"type" => "atom", "text" => Atom.to_string(value)}

  defp tombstone_hash_shape(%DateTime{} = value),
    do: %{"type" => "datetime", "text" => DateTime.to_iso8601(value)}

  defp tombstone_hash_shape(value) when is_list(value) do
    %{
      "type" => "list",
      "length" => length(value),
      "items" => Enum.map(value, &tombstone_hash_shape/1)
    }
  end

  defp tombstone_hash_shape(value) when is_tuple(value) do
    items =
      value
      |> Tuple.to_list()
      |> Enum.map(&tombstone_hash_shape/1)

    %{"type" => "tuple", "tuple_size" => tuple_size(value), "items" => items}
  end

  defp tombstone_hash_shape(%_struct{} = value),
    do: %{"type" => "struct", "module" => value.__struct__ |> Module.split() |> Enum.join(".")}

  defp tombstone_hash_shape(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, nested_value} ->
        {to_string(key), tombstone_hash_shape(nested_value)}
      end)
      |> Map.new()

    %{"type" => "map", "entry_count" => map_size(value), "entries" => entries}
  end

  defp tombstone_hash_shape(value) when is_pid(value), do: %{"type" => "pid"}
  defp tombstone_hash_shape(value) when is_reference(value), do: %{"type" => "reference"}
  defp tombstone_hash_shape(value) when is_port(value), do: %{"type" => "port"}
  defp tombstone_hash_shape(value) when is_function(value), do: %{"type" => "function"}
end
