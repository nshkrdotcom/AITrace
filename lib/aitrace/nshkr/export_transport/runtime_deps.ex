defmodule AITrace.NSHKR.ExportTransport.RuntimeDeps do
  @moduledoc """
  Explicit runtime dependency holder for NSHKR AITrace export transport.
  """

  alias AITrace.NSHKR.ExportTransport

  defstruct transport: ExportTransport.Direct, transport_opts: []

  @type t :: %__MODULE__{transport: module(), transport_opts: keyword()}

  @spec new(keyword()) :: {:ok, t()} | {:error, map()}
  def new(opts \\ []) when is_list(opts) do
    transport = Keyword.get(opts, :transport, ExportTransport.Direct)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    with :ok <- validate_transport(transport),
         :ok <- validate_transport_opts(transport_opts) do
      {:ok, %__MODULE__{transport: transport, transport_opts: transport_opts}}
    end
  end

  @spec export_trace(t(), map(), keyword()) :: ExportTransport.result()
  def export_trace(%__MODULE__{} = deps, request, opts \\ [])
      when is_map(request) and is_list(opts) do
    deps.transport.export_trace(request, Keyword.merge(deps.transport_opts, opts))
  end

  @spec read_export(t(), String.t(), keyword()) :: ExportTransport.result()
  def read_export(%__MODULE__{} = deps, ref, opts \\ []) when is_binary(ref) and is_list(opts) do
    deps.transport.read_export(ref, Keyword.merge(deps.transport_opts, opts))
  end

  defp validate_transport(transport) when is_atom(transport) do
    case Code.ensure_loaded(transport) do
      {:module, ^transport} ->
        if function_exported?(transport, :export_trace, 2) and
             function_exported?(transport, :read_export, 2) do
          :ok
        else
          {:error, %{"code" => "invalid_transport", "transport" => inspect(transport)}}
        end

      _other ->
        {:error, %{"code" => "invalid_transport", "transport" => inspect(transport)}}
    end
  end

  defp validate_transport(_transport), do: {:error, %{"code" => "invalid_transport"}}

  defp validate_transport_opts(opts) when is_list(opts), do: :ok
  defp validate_transport_opts(_opts), do: {:error, %{"code" => "invalid_transport_opts"}}
end
