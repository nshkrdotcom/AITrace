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

  test "collector state is not authoritative proof evidence" do
    assert AITrace.Collector.authoritative_evidence?() == false

    assert %{
             storage: :in_memory_agent,
             authoritative_evidence?: false,
             safe_action: :export_required_for_authoritative_evidence
           } = AITrace.Collector.evidence_posture()
  end

  test "collector loss leaves no authoritative proof without export" do
    trace_id = AITrace.Context.generate_id()

    assert %{trace_id: ^trace_id} = AITrace.Collector.new_trace(trace_id)
    assert %{trace_id: ^trace_id} = AITrace.Collector.get_trace(trace_id)

    assert :ok = AITrace.Collector.clear()
    assert AITrace.Collector.get_trace(trace_id) == nil
    assert AITrace.Collector.authoritative_evidence?() == false
  end

  defp completed_trace(trace_id) do
    trace = Trace.new(trace_id)
    span = Span.new("operation") |> Span.finish()
    Trace.add_span(trace, span)
  end
end
