defmodule AITrace.Redactor do
  @moduledoc """
  Small recursive redaction helpers for trace payloads.
  """

  @sensitive_keys ~w(api_key authorization password secret token)

  @doc "Redacts sensitive keys recursively in maps and lists when mode is `:redacted`."
  @spec redact(term(), atom()) :: term()
  def redact(value, :redacted), do: do_redact(value)
  def redact(value, _mode), do: value

  @doc "Redacts exact materialized secret values recursively."
  @spec redact_values(term(), [String.t()]) :: term()
  def redact_values(value, values) when is_list(values) do
    values = Enum.filter(values, &(is_binary(&1) and &1 != ""))
    do_redact_values(value, values)
  end

  def redact_values(value, _values), do: value

  defp do_redact(value) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      if sensitive_key?(key), do: {key, "<redacted>"}, else: {key, do_redact(nested)}
    end)
  end

  defp do_redact(value) when is_list(value), do: Enum.map(value, &do_redact/1)

  defp do_redact(value) when is_binary(value) do
    if bearer_secret?(value), do: "<redacted>", else: value
  end

  defp do_redact(value), do: value

  defp do_redact_values(value, []), do: value

  defp do_redact_values(value, values) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, do_redact_values(nested, values)} end)
  end

  defp do_redact_values(value, values) when is_list(value) do
    Enum.map(value, &do_redact_values(&1, values))
  end

  defp do_redact_values(value, values) when is_binary(value) do
    Enum.reduce(values, value, fn secret, acc -> String.replace(acc, secret, "<redacted>") end)
  end

  defp do_redact_values(value, _values), do: value

  defp sensitive_key?(key), do: key |> to_key() |> then(&(&1 in @sensitive_keys))
  defp to_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp to_key(key) when is_binary(key), do: String.downcase(key)
  defp to_key(key), do: inspect(key)

  defp bearer_secret?(value) do
    String.contains?(String.downcase(value), "bearer") and String.contains?(value, " ")
  end
end
