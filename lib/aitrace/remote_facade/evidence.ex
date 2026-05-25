defmodule AITrace.RemoteFacade.Evidence do
  @moduledoc """
  AITrace-owned evidence facade for distributed StackLab profiles.

  Trace export can be buffered or executed through a configured export
  transport. The facade validates bounded evidence envelopes and returns
  serializable refs for proof readback.
  """

  alias AITrace.NSHKR.ExportTransport.RuntimeDeps

  @owner_group {__MODULE__, :evidence}
  @required_fields ~w(schema_ref tenant_ref correlation_ref idempotency_key trace_ref redaction_class)

  @spec owner_group() :: {module(), :evidence}
  def owner_group, do: @owner_group

  @spec export_trace(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def export_trace(request, opts \\ []) when is_map(request) and is_list(opts) do
    with :ok <- validate_envelope(request),
         {:ok, deps} <- RuntimeDeps.new(opts) do
      RuntimeDeps.export_trace(deps, request, opts)
    end
  end

  @spec read_export(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def read_export(ref, opts \\ []) when is_binary(ref) and is_list(opts) do
    with :ok <- validate_ref(ref),
         {:ok, deps} <- RuntimeDeps.new(opts) do
      RuntimeDeps.read_export(deps, ref, opts)
    end
  end

  defp validate_envelope(request) do
    case Enum.find(@required_fields, &(string_value(request, &1) == nil)) do
      nil -> :ok
      field -> {:error, error(:invalid_envelope, %{"missing_field" => field})}
    end
  end

  defp validate_ref(ref) do
    if String.trim(ref) == "" do
      {:error, error(:invalid_envelope, %{"missing_field" => "export_ref"})}
    else
      :ok
    end
  end

  defp string_value(map, field) do
    value = Map.get(map, field) || Map.get(map, String.to_atom(field))

    if is_binary(value) and String.trim(value) != "" do
      value
    end
  end

  defp error(code, attrs) do
    Map.merge(
      %{
        "code" => Atom.to_string(code),
        "owner" => "aitrace",
        "facade" => "evidence"
      },
      attrs
    )
  end
end
