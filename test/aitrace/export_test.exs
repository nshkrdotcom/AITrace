defmodule AITrace.ExportTest do
  use ExUnit.Case, async: false

  alias AITrace.{Span, Trace}

  defmodule TestExporter do
    @behaviour AITrace.Exporter

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def export(trace, %{test_pid: test_pid} = state) do
      send(test_pid, {:exported_trace, trace, state})
      {:ok, state}
    end

    @impl true
    def shutdown(%{test_pid: test_pid}) do
      send(test_pid, :exporter_shutdown)
      :ok
    end
  end

  setup do
    previous_exporters = Application.get_env(:aitrace, :exporters)
    on_exit(fn -> Application.put_env(:aitrace, :exporters, previous_exporters) end)
    :ok
  end

  test "exports completed traces through configured exporters" do
    Application.put_env(:aitrace, :exporters, [{TestExporter, test_pid: self()}])
    trace = completed_trace("trace-1")

    assert :ok = AITrace.export(trace)

    assert_receive {:exported_trace, ^trace, %{test_pid: test_pid}}
    assert test_pid == self()
    assert_receive :exporter_shutdown
  end

  test "normalizes keyword exporter options in the direct export path" do
    trace = completed_trace("trace-2")

    assert :ok = AITrace.export(trace, [{TestExporter, [test_pid: self(), tag: :keyword]}])

    assert_receive {:exported_trace, ^trace, %{tag: :keyword, test_pid: test_pid}}
    assert test_pid == self()
    assert_receive :exporter_shutdown
  end

  test "returns unavailable when no exporters are configured" do
    Application.put_env(:aitrace, :exporters, [])

    assert {:error, :unavailable} = AITrace.export(completed_trace("trace-3"))
  end

  defp completed_trace(trace_id) do
    trace = Trace.new(trace_id)
    span = Span.new("operation") |> Span.finish()
    Trace.add_span(trace, span)
  end
end
