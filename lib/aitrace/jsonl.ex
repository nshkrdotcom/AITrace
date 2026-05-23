defmodule AITrace.JSONL do
  @moduledoc """
  Append-only JSONL writer for trace events and receipts.
  """

  @doc "Appends one JSON-normalized event as a single line."
  @spec append(Path.t(), term()) :: :ok | {:error, term()}
  def append(path, event) when is_binary(path) do
    with :ok <- ensure_directory(path),
         {:ok, line} <- encode_line(event) do
      File.write(path, line, [:append])
    end
  end

  @doc "Encodes one event as a JSON line."
  @spec encode_line(term()) :: {:ok, String.t()} | {:error, term()}
  def encode_line(event) do
    event
    |> normalize_for_json()
    |> Jason.encode()
    |> case do
      {:ok, encoded} -> {:ok, encoded <> "\n"}
      {:error, _reason} = error -> error
    end
  end

  @doc "Normalizes atoms, tuples, lists, and maps into JSON-friendly values."
  @spec normalize_for_json(term()) :: term()
  def normalize_for_json(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {normalize_key(key), normalize_for_json(nested)} end)
  end

  def normalize_for_json(value) when is_binary(value), do: value
  def normalize_for_json(value) when is_number(value), do: value
  def normalize_for_json(value) when is_boolean(value), do: value
  def normalize_for_json(nil), do: nil
  def normalize_for_json(value) when is_atom(value), do: Atom.to_string(value)
  def normalize_for_json(value) when is_list(value), do: Enum.map(value, &normalize_for_json/1)

  def normalize_for_json(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&normalize_for_json/1)
  end

  def normalize_for_json(value), do: inspect(value)

  defp ensure_directory(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: to_string(key)
end
