defmodule AITrace.Identifier do
  @moduledoc """
  AITrace-owned identifier policy for generated ids and imported aliases.

  Generated ids keep the existing 32-character lowercase hex shape for API
  compatibility. Caller-supplied ids are accepted only as bounded external
  aliases so proof consumers can distinguish generated ids from imports.
  """

  @id_types [:trace, :span]
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
    if generated_id?(id) do
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
    if external_alias?(id) do
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
    if generated_id?(parent_span_id) do
      source!(:span, parent_span_id, :aitrace_generated)
    else
      source!(:span, parent_span_id, :external_alias)
    end
  end

  defp generated_id?(id) do
    byte_size(id) == 32 and
      id
      |> :binary.bin_to_list()
      |> Enum.all?(&lower_hex_byte?/1)
  end

  defp external_alias?(<<first, rest::binary>>) do
    byte_size(rest) <= 127 and alnum_byte?(first) and
      rest
      |> :binary.bin_to_list()
      |> Enum.all?(&external_alias_rest_byte?/1)
  end

  defp external_alias?(_id), do: false

  defp lower_hex_byte?(byte), do: byte in ?0..?9 or byte in ?a..?f

  defp alnum_byte?(byte), do: byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9

  defp external_alias_rest_byte?(byte),
    do: alnum_byte?(byte) or byte in [?., ?_, ?:, ?-]
end
