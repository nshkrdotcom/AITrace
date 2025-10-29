defmodule AITrace.SpanTest do
  use ExUnit.Case, async: true

  alias AITrace.Span

  describe "new/2" do
    test "creates a new span with generated span_id" do
      span = Span.new("test_operation")

      assert %Span{} = span
      assert is_binary(span.span_id)
      assert byte_size(span.span_id) == 32
    end

    test "creates unique span_ids for each span" do
      span1 = Span.new("op1")
      span2 = Span.new("op2")

      assert span1.span_id != span2.span_id
    end

    test "sets the span name" do
      span = Span.new("my_operation")

      assert span.name == "my_operation"
    end

    test "sets start_time to current monotonic time" do
      before = System.monotonic_time(:microsecond)
      span = Span.new("test")
      after_time = System.monotonic_time(:microsecond)

      assert span.start_time >= before
      assert span.start_time <= after_time
    end

    test "initializes end_time as nil" do
      span = Span.new("test")

      assert span.end_time == nil
    end

    test "initializes with nil parent_span_id" do
      span = Span.new("test")

      assert span.parent_span_id == nil
    end

    test "initializes with empty attributes" do
      span = Span.new("test")

      assert span.attributes == %{}
    end

    test "initializes with empty events list" do
      span = Span.new("test")

      assert span.events == []
    end

    test "sets status to :ok by default" do
      span = Span.new("test")

      assert span.status == :ok
    end
  end

  describe "new/3 with parent_span_id" do
    test "creates span with parent_span_id" do
      span = Span.new("child_op", "parent_123")

      assert span.parent_span_id == "parent_123"
      assert span.name == "child_op"
    end
  end

  describe "finish/1" do
    test "sets end_time to current monotonic time" do
      span = Span.new("test")
      # Ensure time passes
      Process.sleep(1)

      finished_span = Span.finish(span)

      assert finished_span.end_time != nil
      assert finished_span.end_time > finished_span.start_time
    end

    test "returns a new span (immutability)" do
      span = Span.new("test")
      finished_span = Span.finish(span)

      assert span.end_time == nil
      assert finished_span.end_time != nil
      refute span == finished_span
    end
  end

  describe "with_attributes/2" do
    test "adds attributes to span" do
      span = Span.new("test")
      attrs = %{user_id: 42, action: "fetch"}

      new_span = Span.with_attributes(span, attrs)

      assert new_span.attributes == attrs
    end

    test "merges with existing attributes" do
      span = Span.new("test") |> Span.with_attributes(%{a: 1})
      new_span = Span.with_attributes(span, %{b: 2})

      assert new_span.attributes == %{a: 1, b: 2}
    end

    test "overwrites existing keys" do
      span = Span.new("test") |> Span.with_attributes(%{a: 1})
      new_span = Span.with_attributes(span, %{a: 2})

      assert new_span.attributes == %{a: 2}
    end
  end

  describe "add_event/2" do
    test "appends an event to the events list" do
      span = Span.new("test")

      event = %AITrace.Event{
        name: "validation_failed",
        timestamp: System.monotonic_time(:microsecond)
      }

      new_span = Span.add_event(span, event)

      assert length(new_span.events) == 1
      assert hd(new_span.events) == event
    end

    test "maintains event order" do
      span = Span.new("test")
      event1 = %AITrace.Event{name: "event1", timestamp: System.monotonic_time(:microsecond)}
      event2 = %AITrace.Event{name: "event2", timestamp: System.monotonic_time(:microsecond)}

      new_span =
        span
        |> Span.add_event(event1)
        |> Span.add_event(event2)

      assert new_span.events == [event1, event2]
    end
  end

  describe "with_status/2" do
    test "sets span status to :error" do
      span = Span.new("test")
      new_span = Span.with_status(span, :error)

      assert new_span.status == :error
    end

    test "accepts :ok status" do
      span = Span.new("test")
      new_span = Span.with_status(span, :ok)

      assert new_span.status == :ok
    end
  end

  describe "duration/1" do
    test "returns nil if span is not finished" do
      span = Span.new("test")

      assert Span.duration(span) == nil
    end

    test "returns duration in microseconds for finished span" do
      span = Span.new("test")
      Process.sleep(2)
      finished_span = Span.finish(span)

      duration = Span.duration(finished_span)

      assert is_integer(duration)
      # At least 2ms
      assert duration >= 2000
      # Less than 1 second
      assert duration < 1_000_000
    end
  end
end
