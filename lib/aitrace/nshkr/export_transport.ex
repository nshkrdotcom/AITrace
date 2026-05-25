defmodule AITrace.NSHKR.ExportTransport do
  @moduledoc """
  Transport contract for NSHKR owner nodes exporting trace/evidence facts.
  """

  @type result :: {:ok, map()} | {:error, map()}

  @callback export_trace(request :: map(), opts :: keyword()) :: result()
  @callback read_export(ref :: String.t(), opts :: keyword()) :: result()
end
