defmodule AITrace.Identifier do
  @moduledoc """
  AITrace-owned identifier policy for generated ids and imported aliases.

  Generated ids keep the existing 32-character lowercase hex shape for API
  compatibility. Caller-supplied ids are accepted only as bounded external
  aliases so proof consumers can distinguish generated ids from imports.
  """

  @id_types [:trace, :span]
  @generated_regex ~r/\A[0-9a-f]{32}\z/
  @external_alias_regex ~r/\A[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\z/
  @generated_policy "aitrace-id-v1"
  @external_alias_policy "aitrace-external-alias-v1"

  @type id_type :: :trace | :span
  @type source_kind :: :aitrace_generated | :external_alias

  @spec generate(id_type()) :: String.t()
  def generate(id_type) when id_type in @id_types do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  @spec source!(id_type(), String.t(), source_kind()) :: map()
  def source!(id_type, id, :aitrace_generated) when id_type in @id_types and is_binary(id) do
    if Regex.match?(@generated_regex, id) do
      %{
        id_type: id_type,
        kind: :aitrace_generated,
        policy: @generated_policy,
        algorithm: "crypto.strong_rand_bytes",
        entropy_bytes: 16,
        encoding: "base16_lower",
        prefix: nil,
        prefix_policy: "none_backcompat_32_hex"
      }
    else
      raise ArgumentError,
            "invalid AITrace-generated #{id_type} id: expected 32 lowercase hex characters"
    end
  end

  def source!(id_type, id, :external_alias) when id_type in @id_types and is_binary(id) do
    if Regex.match?(@external_alias_regex, id) do
      %{
        id_type: id_type,
        kind: :external_alias,
        policy: @external_alias_policy,
        validation: "bounded_external_alias",
        max_bytes: 128
      }
    else
      raise ArgumentError,
            "invalid external #{id_type} alias: expected 1-128 chars of [A-Za-z0-9._:-] starting with alnum"
    end
  end

  @spec parent_span_source!(String.t()) :: map()
  def parent_span_source!(parent_span_id) when is_binary(parent_span_id) do
    if Regex.match?(@generated_regex, parent_span_id) do
      source!(:span, parent_span_id, :aitrace_generated)
    else
      source!(:span, parent_span_id, :external_alias)
    end
  end
end
