defmodule AITrace.NSHKR.ExportTransport.Fixture do
  @moduledoc """
  Deterministic AITrace export transport for tests.
  """

  @behaviour AITrace.NSHKR.ExportTransport

  @impl true
  def export_trace(request, opts) when is_map(request) and is_list(opts) do
    reply(opts, :export_trace, [request, opts], fn ->
      {:ok,
       %{
         "status" => "exported",
         "export_ref" => Map.get(request, "trace_ref", "trace://fixture/export"),
         "correlation_ref" => Map.get(request, "correlation_ref", "correlation://fixture/aitrace")
       }}
    end)
  end

  @impl true
  def read_export(ref, opts) when is_binary(ref) and is_list(opts) do
    reply(opts, :read_export, [ref, opts], fn ->
      {:ok, %{"status" => "available", "export_ref" => ref}}
    end)
  end

  defp reply(opts, callback, args, default) do
    opts
    |> configured_response(callback)
    |> case do
      nil -> default.()
      fun when is_function(fun, length(args)) -> apply(fun, args)
      fun when is_function(fun, length(args) - 1) -> apply(fun, Enum.drop(args, -1))
      result -> result
    end
    |> normalize_result()
  end

  defp configured_response(opts, callback) do
    responses = Keyword.get(opts, :responses, %{})

    Keyword.get(opts, callback) || Map.get(responses, callback) ||
      Map.get(responses, Atom.to_string(callback))
  end

  defp normalize_result({:ok, result}) when is_map(result), do: {:ok, result}
  defp normalize_result({:error, reason}) when is_map(reason), do: {:error, reason}
  defp normalize_result(result) when is_map(result), do: {:ok, result}

  defp normalize_result(reason),
    do: {:error, error(:invalid_fixture_response, %{"reason" => inspect(reason)})}

  defp error(code, attrs),
    do: Map.merge(%{"code" => Atom.to_string(code), "transport" => "fixture"}, attrs)
end
