defmodule AITrace.TraceTest do
  use ExUnit.Case, async: true

  alias AITrace.{Trace, Span}

  describe "new/1" do
    test "creates a new trace with a trace_id" do
      trace = Trace.new("trace_123")

      assert %Trace{} = trace
      assert trace.trace_id == "trace_123"
    end

    test "initializes with empty spans list" do
      trace = Trace.new("trace_123")

      assert trace.spans == []
    end

    test "initializes with empty metadata" do
      trace = Trace.new("trace_123")

      assert trace.metadata == %{}
    end

    test "sets created_at timestamp" do
      before = System.monotonic_time(:microsecond)
      trace = Trace.new("trace_123")
      after_time = System.monotonic_time(:microsecond)

      assert trace.created_at >= before
      assert trace.created_at <= after_time
    end
  end

  describe "add_span/2" do
    test "adds a span to the trace" do
      trace = Trace.new("trace_123")
      span = Span.new("operation")

      new_trace = Trace.add_span(trace, span)

      assert length(new_trace.spans) == 1
      assert hd(new_trace.spans) == span
    end

    test "maintains span order" do
      trace = Trace.new("trace_123")
      span1 = Span.new("op1")
      span2 = Span.new("op2")

      new_trace =
        trace
        |> Trace.add_span(span1)
        |> Trace.add_span(span2)

      assert new_trace.spans == [span1, span2]
    end

    test "preserves immutability" do
      trace = Trace.new("trace_123")
      span = Span.new("operation")

      new_trace = Trace.add_span(trace, span)

      assert trace.spans == []
      assert length(new_trace.spans) == 1
    end
  end

  describe "get_span/2" do
    test "retrieves span by span_id" do
      trace = Trace.new("trace_123")
      span = Span.new("operation")
      trace = Trace.add_span(trace, span)

      retrieved = Trace.get_span(trace, span.span_id)

      assert retrieved == span
    end

    test "returns nil if span not found" do
      trace = Trace.new("trace_123")

      assert Trace.get_span(trace, "nonexistent") == nil
    end
  end

  describe "with_metadata/2" do
    test "adds metadata to trace" do
      trace = Trace.new("trace_123")
      metadata = %{user_id: 42, session: "abc"}

      new_trace = Trace.with_metadata(trace, metadata)

      assert new_trace.metadata == metadata
    end

    test "merges with existing metadata" do
      trace = Trace.new("trace_123") |> Trace.with_metadata(%{a: 1})
      new_trace = Trace.with_metadata(trace, %{b: 2})

      assert new_trace.metadata == %{a: 1, b: 2}
    end
  end

  describe "get_root_spans/1" do
    test "returns spans with no parent" do
      trace = Trace.new("trace_123")
      root_span = Span.new("root")
      child_span = Span.new("child", root_span.span_id)

      trace =
        trace
        |> Trace.add_span(root_span)
        |> Trace.add_span(child_span)

      roots = Trace.get_root_spans(trace)

      assert length(roots) == 1
      assert hd(roots) == root_span
    end

    test "returns empty list when no spans" do
      trace = Trace.new("trace_123")

      assert Trace.get_root_spans(trace) == []
    end

    test "returns multiple root spans" do
      trace = Trace.new("trace_123")
      root1 = Span.new("root1")
      root2 = Span.new("root2")

      trace =
        trace
        |> Trace.add_span(root1)
        |> Trace.add_span(root2)

      roots = Trace.get_root_spans(trace)

      assert length(roots) == 2
    end
  end

  describe "get_children/2" do
    test "returns child spans of a given parent" do
      trace = Trace.new("trace_123")
      root = Span.new("root")
      child1 = Span.new("child1", root.span_id)
      child2 = Span.new("child2", root.span_id)
      other = Span.new("other")

      trace =
        trace
        |> Trace.add_span(root)
        |> Trace.add_span(child1)
        |> Trace.add_span(child2)
        |> Trace.add_span(other)

      children = Trace.get_children(trace, root.span_id)

      assert length(children) == 2
      assert child1 in children
      assert child2 in children
    end

    test "returns empty list when no children" do
      trace = Trace.new("trace_123")
      root = Span.new("root")
      trace = Trace.add_span(trace, root)

      assert Trace.get_children(trace, root.span_id) == []
    end
  end
end
