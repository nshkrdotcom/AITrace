defmodule AITrace.Hash do
  @moduledoc """
  Deterministic content hashing helpers for trace compatibility.

  These helpers are intentionally value-oriented. They normalize maps, atoms,
  lists, tuples, numbers, and binaries before SHA-256 hashing, so callers can
  produce stable refs without depending on runtime map ordering.
  """

  @type hash :: String.t()

  @doc "Hashes any term with deterministic normalization and serialization."
  @spec term(term()) :: hash()
  def term(value) do
    value
    |> normalize_for_hash()
    |> :erlang.term_to_binary([:compressed])
    |> bytes()
  end

  @doc "Hashes a transcript represented as role/content maps."
  @spec messages([map()]) :: hash()
  def messages(messages) when is_list(messages) do
    messages
    |> Enum.map(&message_for_hash/1)
    |> term()
  end

  @doc "Hashes text or response payloads."
  @spec text(String.t()) :: hash()
  def text(value) when is_binary(value), do: term(%{text: value})

  @doc "Hashes trace metadata maps."
  @spec metadata(map()) :: hash()
  def metadata(map) when is_map(map), do: term(map)

  @doc "Hashes raw binary content as lowercase SHA-256 hex."
  @spec bytes(binary()) :: hash()
  def bytes(binary) when is_binary(binary) do
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end

  @doc "Normalizes a value into the deterministic shape used by `term/1`."
  @spec normalize_for_hash(term()) :: term()
  def normalize_for_hash(value) when is_map(value) do
    value
    |> Enum.to_list()
    |> Enum.sort_by(fn {key, _value} -> normalize_key(key) end)
    |> Enum.map(fn {key, nested} -> {normalize_key(key), normalize_for_hash(nested)} end)
    |> Map.new()
  end

  def normalize_for_hash(value) when is_list(value), do: Enum.map(value, &normalize_for_hash/1)

  def normalize_for_hash(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&normalize_for_hash/1)
  end

  def normalize_for_hash(value) when is_atom(value), do: Atom.to_string(value)
  def normalize_for_hash(value) when is_number(value), do: value
  def normalize_for_hash(value) when is_binary(value), do: value
  def normalize_for_hash(value), do: inspect(value)

  defp message_for_hash(message) do
    %{
      role: Map.get(message, :role, Map.get(message, "role")),
      content: Map.get(message, :content, Map.get(message, "content"))
    }
  end

  defp normalize_key(nil), do: ""
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_integer(key), do: Integer.to_string(key)
  defp normalize_key(key), do: inspect(key)
end
