defmodule AITrace.ExporterTest do
  use ExUnit.Case, async: true

  alias AITrace.{Trace, Span}

  # Test implementation for testing purposes
  defmodule TestExporter do
    @behaviour AITrace.Exporter

    def init(opts) do
      {:ok, opts}
    end

    def export(trace, state) do
      # Store trace in process dictionary for testing
      Process.put(:last_exported_trace, trace)
      {:ok, state}
    end

    def shutdown(_state) do
      Process.put(:exporter_shutdown, true)
      :ok
    end
  end

  describe "behavior callbacks" do
    test "init/1 is required" do
      callbacks = AITrace.Exporter.behaviour_info(:callbacks)

      assert {:init, 1} in callbacks
    end

    test "export/2 is required" do
      callbacks = AITrace.Exporter.behaviour_info(:callbacks)

      assert {:export, 2} in callbacks
    end

    test "shutdown/1 is required" do
      callbacks = AITrace.Exporter.behaviour_info(:callbacks)

      assert {:shutdown, 1} in callbacks
    end
  end

  describe "TestExporter implementation" do
    test "can be initialized" do
      assert {:ok, %{test: true}} = TestExporter.init(%{test: true})
    end

    test "can export a trace" do
      trace = Trace.new("test_trace")
      span = Span.new("operation")
      trace = Trace.add_span(trace, span)

      {:ok, _state} = TestExporter.export(trace, %{})

      assert Process.get(:last_exported_trace) == trace
    end

    test "can be shutdown" do
      assert :ok = TestExporter.shutdown(%{})
      assert Process.get(:exporter_shutdown) == true
    end
  end
end
