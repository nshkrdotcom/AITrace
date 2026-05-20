defmodule AITrace.Telemetry do
  @moduledoc false

  @spec execute([atom()], map(), map()) :: :ok
  def execute(event, measurements, metadata)
      when is_list(event) and is_map(measurements) and is_map(metadata) do
    :telemetry.execute(event, measurements, metadata)
    :ok
  end
end
