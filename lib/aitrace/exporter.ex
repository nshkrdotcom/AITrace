defmodule AITrace.Exporter do
  @moduledoc """
  Behavior for trace exporters.

  Exporters are responsible for sending trace data to various backends.
  This allows AITrace to be pluggable and integrate with different observability systems.

  ## Example Implementations

  - `AITrace.Exporter.Console` - Print traces to stdout for development
  - `AITrace.Exporter.File` - Write traces to JSON files
  - `AITrace.Exporter.Phoenix` - Send traces via Phoenix channels
  - `AITrace.Exporter.OpenTelemetry` - Export to OTel-compatible systems

  ## Implementing an Exporter

      defmodule MyApp.CustomExporter do
        @behaviour AITrace.Exporter

        @impl true
        def init(opts) do
          # Initialize exporter state
          {:ok, opts}
        end

        @impl true
        def export(trace, state) do
          # Send the trace somewhere
          IO.inspect(trace)
          {:ok, state}
        end

        @impl true
        def shutdown(state) do
          # Cleanup resources
          :ok
        end
      end
  """

  alias AITrace.Trace

  @doc """
  Initialize the exporter with the given options.

  Returns `{:ok, state}` on success, or `{:error, reason}` on failure.
  """
  @callback init(opts :: map()) :: {:ok, state :: any()} | {:error, reason :: any()}

  @doc """
  Export a trace to the backend.

  The exporter should send the trace data to its destination and return
  `{:ok, new_state}` on success, or `{:error, reason}` on failure.
  """
  @callback export(trace :: Trace.t(), state :: any()) ::
              {:ok, state :: any()} | {:error, reason :: any()}

  @doc """
  Shutdown the exporter and cleanup any resources.

  This is called when the exporter is being stopped.
  """
  @callback shutdown(state :: any()) :: :ok
end
