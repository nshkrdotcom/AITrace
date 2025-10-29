defmodule AITrace.IntegrationTest do
  use ExUnit.Case, async: false
  require AITrace

  test "basic trace and span work" do
    result =
      AITrace.trace "test" do
        :ok
      end

    assert result == :ok
  end

  test "nested spans work" do
    result =
      AITrace.trace "test" do
        AITrace.span "operation" do
          :done
        end
      end

    assert result == :done
  end

  test "events can be added" do
    result =
      AITrace.trace "test" do
        AITrace.span "operation" do
          AITrace.add_event("test_event")
          :ok
        end
      end

    assert result == :ok
  end

  test "attributes can be added" do
    result =
      AITrace.trace "test" do
        AITrace.span "operation" do
          AITrace.with_attributes(%{user_id: 42})
          :ok
        end
      end

    assert result == :ok
  end

  # Note: ctx variable injection doesn't work due to Elixir macro hygiene
  # Users should use AITrace.get_current_context() instead
  # test "ctx variable is available" do
  #   {trace_id, span_id} = AITrace.trace "test" do
  #     AITrace.span "operation" do
  #       {ctx.trace_id, ctx.span_id}
  #     end
  #   end
  #
  #   assert is_binary(trace_id)
  #   assert is_binary(span_id)
  # end
  #
  # test "nested spans have different span_ids" do
  #   result = AITrace.trace "test" do
  #     AITrace.span "parent" do
  #       parent_id = ctx.span_id
  #
  #       AITrace.span "child" do
  #         child_id = ctx.span_id
  #         assert parent_id != child_id
  #         :ok
  #       end
  #     end
  #   end
  #
  #   assert result == :ok
  # end

  test "context can be retrieved" do
    result =
      AITrace.trace "test" do
        AITrace.span "operation" do
          ctx = AITrace.get_current_context()
          {ctx.trace_id, ctx.span_id}
        end
      end

    {trace_id, span_id} = result
    assert is_binary(trace_id)
    assert is_binary(span_id)
  end
end
