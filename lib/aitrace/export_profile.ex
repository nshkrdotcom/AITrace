defmodule AITrace.ExportProfile do
  @moduledoc """
  Explicit export configuration captured by a trace context.

  Standalone callers may rely on the boot default profile derived from
  application config. Governed callers should construct and pass a profile at
  the call site so export sinks are data on the trace context, not ambient VM
  state consulted at finish time.
  """

  @type exporter_config :: module() | {module(), keyword() | map()}

  @type t :: %__MODULE__{
          exporters: [exporter_config()],
          source: :explicit | :boot_default,
          metadata: map()
        }

  defstruct exporters: [], source: :explicit, metadata: %{}

  @doc """
  Builds an explicit export profile.
  """
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      exporters: Map.get(attrs, :exporters, []),
      source: Map.get(attrs, :source, :explicit),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @doc """
  Captures the application-configured exporters as a boot default profile.
  """
  @spec boot_default() :: t()
  def boot_default do
    new(
      exporters: Application.get_env(:aitrace, :exporters) || [],
      source: :boot_default
    )
  end

  defp normalize_attrs(attrs) when is_map(attrs), do: attrs

  defp normalize_attrs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      Map.new(attrs)
    else
      raise ArgumentError, "export profile attributes must be a keyword list or map"
    end
  end
end
