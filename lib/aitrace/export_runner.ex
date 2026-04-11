defmodule AITrace.ExportRunner do
  @moduledoc false

  alias AITrace.Trace

  @type exporter_config :: module() | {module(), keyword() | map()}

  @spec export(Trace.t(), [exporter_config()]) :: :ok | {:error, term()}
  def export(%Trace{} = trace, exporters) when is_list(exporters) do
    case exporters do
      [] ->
        {:error, :unavailable}

      _ ->
        Enum.reduce_while(exporters, :ok, fn exporter_config, :ok ->
          case normalize_exporter(exporter_config) do
            {:ok, exporter_module, opts} ->
              case normalize_result(exporter_module.init(opts)) do
                {:ok, state} ->
                  case normalize_result(exporter_module.export(trace, state)) do
                    {:ok, next_state} ->
                      maybe_shutdown(exporter_module, next_state)
                      {:cont, :ok}

                    {:error, reason} ->
                      maybe_shutdown(exporter_module, state)
                      {:halt, {:error, reason}}
                  end

                {:error, reason} ->
                  {:halt, {:error, reason}}
              end

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp normalize_exporter({exporter_module, opts}) when is_atom(exporter_module) do
    with {:ok, normalized_opts} <- normalize_opts(opts) do
      {:ok, exporter_module, normalized_opts}
    end
  end

  defp normalize_exporter(exporter_module) when is_atom(exporter_module) do
    {:ok, exporter_module, %{}}
  end

  defp normalize_exporter(_other), do: {:error, :invalid_exporter_config}

  defp normalize_opts(nil), do: {:ok, %{}}
  defp normalize_opts(opts) when is_map(opts), do: {:ok, opts}

  defp normalize_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, Map.new(opts)}
    else
      {:error, :invalid_exporter_options}
    end
  end

  defp normalize_opts(_other), do: {:error, :invalid_exporter_options}

  defp normalize_result({:ok, state}), do: {:ok, state}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result(_other), do: {:error, :backend_rejected}

  defp maybe_shutdown(module, state) do
    if function_exported?(module, :shutdown, 1) do
      module.shutdown(state)
    end
  end
end
