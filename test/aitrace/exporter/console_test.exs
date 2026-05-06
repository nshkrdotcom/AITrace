defmodule AITrace.Exporter.ConsoleTest do
  # Not async because we capture IO
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AITrace.{Event, Exporter.Console, Span, Trace}

  describe "init/1" do
    test "initializes with default options" do
      assert {:ok, state} = Console.init(%{})
      assert is_map(state)
    end

    test "accepts custom options" do
      opts = %{color: true, verbose: true}
      assert {:ok, state} = Console.init(opts)
      assert state.color == true
      assert state.verbose == true
    end
  end

  describe "export/2" do
    test "prints trace information to stdout" do
      trace = Trace.new("test_trace_123")

      span =
        Span.new("root_operation")
        |> Span.with_attributes(%{user_id: 42})
        |> Span.finish()

      trace = Trace.add_span(trace, span)

      {:ok, state} = Console.init(%{})

      output =
        capture_io(fn ->
          Console.export(trace, state)
        end)

      assert String.contains?(output, "Trace: test_trace_123")
      assert String.contains?(output, "root_operation")
    end

    test "displays span hierarchy" do
      trace = Trace.new("trace_123")
      root = Span.new("root") |> Span.finish()
      child = Span.new("child", root.span_id) |> Span.finish()

      trace =
        trace
        |> Trace.add_span(root)
        |> Trace.add_span(child)

      {:ok, state} = Console.init(%{})

      output =
        capture_io(fn ->
          Console.export(trace, state)
        end)

      assert String.contains?(output, "root")
      assert String.contains?(output, "child")
    end

    test "shows span duration when available" do
      trace = Trace.new("trace_123")
      span = Span.new("operation")
      Process.sleep(1)
      span = Span.finish(span)

      trace = Trace.add_span(trace, span)

      {:ok, state} = Console.init(%{})

      output =
        capture_io(fn ->
          Console.export(trace, state)
        end)

      duration_line =
        output
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, "operation"))

      assert is_binary(duration_line)
      assert String.contains?(duration_line, "(")
      assert Enum.any?(["μs)", "ms)", "s)"], &String.contains?(duration_line, &1))
    end

    test "displays span attributes in verbose mode" do
      trace = Trace.new("trace_123")

      span =
        Span.new("operation")
        |> Span.with_attributes(%{user_id: 42, action: "fetch"})
        |> Span.finish()

      trace = Trace.add_span(trace, span)

      output =
        capture_io(fn ->
          Console.export(trace, %{verbose: true})
        end)

      assert String.contains?(output, "user_id")
      assert String.contains?(output, "42")
    end

    test "displays events within spans" do
      trace = Trace.new("trace_123")
      event = Event.new("cache_miss", %{key: "user_123"})

      span =
        Span.new("operation")
        |> Span.add_event(event)
        |> Span.finish()

      trace = Trace.add_span(trace, span)

      output =
        capture_io(fn ->
          Console.export(trace, %{verbose: true})
        end)

      assert String.contains?(output, "cache_miss")
    end
  end

  describe "shutdown/1" do
    test "returns :ok" do
      assert :ok = Console.shutdown(%{})
    end
  end
end
