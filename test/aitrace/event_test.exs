defmodule AITrace.EventTest do
  use ExUnit.Case, async: true

  alias AITrace.Event

  describe "new/2" do
    test "creates a new event with name and attributes" do
      attrs = %{error_code: 404, message: "Not found"}
      event = Event.new("http_error", attrs)

      assert %Event{} = event
      assert event.name == "http_error"
      assert event.attributes == attrs
    end

    test "sets timestamp to current monotonic time" do
      before = System.monotonic_time(:microsecond)
      event = Event.new("test_event", %{})
      after_time = System.monotonic_time(:microsecond)

      assert event.timestamp >= before
      assert event.timestamp <= after_time
    end

    test "allows empty attributes" do
      event = Event.new("simple_event", %{})

      assert event.attributes == %{}
    end
  end

  describe "new/1" do
    test "creates event with just a name" do
      event = Event.new("checkpoint_reached")

      assert event.name == "checkpoint_reached"
      assert event.attributes == %{}
      assert is_integer(event.timestamp)
    end
  end
end
