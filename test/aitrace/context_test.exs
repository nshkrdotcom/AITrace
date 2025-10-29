defmodule AITrace.ContextTest do
  use ExUnit.Case, async: true

  alias AITrace.Context

  describe "new/0" do
    test "creates a new context with a trace_id" do
      ctx = Context.new()

      assert %Context{} = ctx
      assert is_binary(ctx.trace_id)
      # UUID without dashes
      assert byte_size(ctx.trace_id) == 32
    end

    test "creates unique trace_ids for each context" do
      ctx1 = Context.new()
      ctx2 = Context.new()

      assert ctx1.trace_id != ctx2.trace_id
    end

    test "initializes with nil span_id" do
      ctx = Context.new()

      assert ctx.span_id == nil
    end

    test "initializes with empty metadata" do
      ctx = Context.new()

      assert ctx.metadata == %{}
    end
  end

  describe "new/1 with trace_id" do
    test "creates context with provided trace_id" do
      trace_id = "custom_trace_123"
      ctx = Context.new(trace_id)

      assert ctx.trace_id == trace_id
    end
  end

  describe "with_span_id/2" do
    test "returns new context with updated span_id" do
      ctx = Context.new()
      span_id = "span_123"

      new_ctx = Context.with_span_id(ctx, span_id)

      assert new_ctx.span_id == span_id
      assert new_ctx.trace_id == ctx.trace_id
      # Immutability check
      refute new_ctx == ctx
    end
  end

  describe "with_metadata/2" do
    test "returns new context with merged metadata" do
      ctx = Context.new()
      metadata = %{user_id: 42, session: "abc"}

      new_ctx = Context.with_metadata(ctx, metadata)

      assert new_ctx.metadata == metadata
      assert new_ctx.trace_id == ctx.trace_id
    end

    test "merges with existing metadata" do
      ctx = Context.new() |> Context.with_metadata(%{a: 1})
      new_ctx = Context.with_metadata(ctx, %{b: 2})

      assert new_ctx.metadata == %{a: 1, b: 2}
    end

    test "overwrites existing keys" do
      ctx = Context.new() |> Context.with_metadata(%{a: 1})
      new_ctx = Context.with_metadata(ctx, %{a: 2})

      assert new_ctx.metadata == %{a: 2}
    end
  end

  describe "get_metadata/2" do
    test "retrieves metadata by key" do
      ctx = Context.new() |> Context.with_metadata(%{user_id: 42})

      assert Context.get_metadata(ctx, :user_id) == 42
    end

    test "returns nil for missing keys" do
      ctx = Context.new()

      assert Context.get_metadata(ctx, :missing) == nil
    end

    test "returns default value for missing keys" do
      ctx = Context.new()

      assert Context.get_metadata(ctx, :missing, :default) == :default
    end
  end
end
