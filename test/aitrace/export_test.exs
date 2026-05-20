defmodule AITrace.ExportTest do
  use ExUnit.Case, async: false

  alias AITrace.{ExportProfile, Span, Trace}

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

  defmodule AmbientExporter do
    @behaviour AITrace.Exporter

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def export(trace, %{test_pid: test_pid} = state) do
      send(test_pid, {:ambient_exported_trace, trace, state})
      {:ok, state}
    end

    @impl true
    def shutdown(_state), do: :ok
  end

  setup do
    previous_exporters = Application.get_env(:aitrace, :exporters)
    on_exit(fn -> restore_app_env(:aitrace, :exporters, previous_exporters) end)
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

  test "explicit export path ignores ambient application env exporters" do
    Application.put_env(:aitrace, :exporters, [{AmbientExporter, test_pid: self()}])
    trace = completed_trace("trace-explicit")

    assert :ok = AITrace.export(trace, [{TestExporter, test_pid: self(), tag: :explicit}])

    assert_receive {:exported_trace, ^trace, %{tag: :explicit, test_pid: test_pid}}
    assert test_pid == self()
    assert_receive :exporter_shutdown
    refute_received {:ambient_exported_trace, _trace, _state}
  end

  test "export profiles ignore ambient application env exporters" do
    Application.put_env(:aitrace, :exporters, [{AmbientExporter, test_pid: self()}])
    trace = completed_trace("trace-profile")
    profile = ExportProfile.new(exporters: [{TestExporter, test_pid: self(), tag: :profile}])

    assert :ok = AITrace.export(trace, profile)

    assert_receive {:exported_trace, ^trace, %{tag: :profile, test_pid: test_pid}}
    assert test_pid == self()
    assert_receive :exporter_shutdown
    refute_received {:ambient_exported_trace, _trace, _state}
  end

  test "trace context captures explicit export profile for finish" do
    Application.put_env(:aitrace, :exporters, [{AmbientExporter, test_pid: self()}])
    profile = ExportProfile.new(exporters: [{TestExporter, test_pid: self(), tag: :run_trace}])

    assert :ok =
             AITrace.run_trace(
               "profiled_run",
               fn ctx ->
                 assert ctx.export_profile == profile

                 AITrace.run_span(ctx, "profiled_span", fn span_ctx ->
                   AITrace.with_attributes(span_ctx, %{profiled: true})
                   :ok
                 end)
               end,
               export_profile: profile
             )

    assert_receive {:exported_trace, %Trace{} = trace, %{tag: :run_trace, test_pid: test_pid}}
    assert test_pid == self()
    assert [_span] = trace.spans
    assert_receive :exporter_shutdown
    refute_received {:ambient_exported_trace, _trace, _state}
  end

  test "trace context captures boot default exporters at creation" do
    Application.put_env(:aitrace, :exporters, [
      {TestExporter, test_pid: self(), tag: :boot_default}
    ])

    ctx = AITrace.start_trace("boot_default_capture")

    Application.put_env(:aitrace, :exporters, [{AmbientExporter, test_pid: self()}])

    span_ctx = AITrace.start_span(ctx, "captured_span")
    assert :ok = AITrace.finish_span(span_ctx)
    assert :ok = AITrace.finish_trace(ctx)

    assert_receive {:exported_trace, %Trace{}, %{tag: :boot_default, test_pid: test_pid}}
    assert test_pid == self()
    assert_receive :exporter_shutdown
    refute_received {:ambient_exported_trace, _trace, _state}
  end

  test "returns unavailable when no exporters are configured" do
    Application.put_env(:aitrace, :exporters, [])

    assert {:error, :unavailable} = AITrace.export(completed_trace("trace-3"))
  end

  test "capture off skips trace retention without failing the caller" do
    Application.put_env(:aitrace, :exporters, [])

    trace =
      "trace-off"
      |> completed_trace()
      |> Trace.with_persistence_posture(persistence_profile: :off)

    assert :ok = AITrace.export(trace)
  end

  test "collector state is not authoritative proof evidence" do
    assert AITrace.Collector.authoritative_evidence?() == false

    assert %{
             storage: :supervised_trace_owners,
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

  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)
end
