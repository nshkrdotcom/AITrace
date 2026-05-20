defmodule AITrace.ExplicitContextApiTest do
  use ExUnit.Case, async: false
  require AITrace

  alias AITrace.{Context, Span, Trace}

  defmodule TestExporter do
    @behaviour AITrace.Exporter

    @impl true
    def init(opts), do: {:ok, Map.new(opts)}

    @impl true
    def export(trace, %{test_pid: test_pid} = state) do
      send(test_pid, {:exported_trace, trace, state})
      {:ok, state}
    end

    @impl true
    def shutdown(_state), do: :ok
  end

  setup do
    previous_exporters = Application.get_env(:aitrace, :exporters)

    Application.put_env(:aitrace, :exporters, [{TestExporter, test_pid: self()}])
    AITrace.Collector.clear()
    AITrace.clear_current_context()

    on_exit(fn ->
      restore_app_env(:aitrace, :exporters, previous_exporters)
      AITrace.clear_current_context()
      AITrace.Collector.clear()
    end)

    :ok
  end

  test "explicit context APIs propagate across task boundaries without process dictionary context" do
    {parent_span_id, child_span_id} =
      AITrace.run_trace("explicit_task_boundary", fn trace_ctx ->
        assert %Context{span_id: nil} = trace_ctx
        assert AITrace.get_current_context() == nil

        AITrace.run_span(trace_ctx, "parent", fn parent_ctx ->
          AITrace.add_event(parent_ctx, "parent_event")

          task =
            Task.async(fn ->
              assert AITrace.get_current_context() == nil

              AITrace.run_span(parent_ctx, "child_task", fn child_ctx ->
                AITrace.add_event(child_ctx, "task_event", %{source: "task"})
                AITrace.with_attributes(child_ctx, %{task_boundary: true})
                child_ctx.span_id
              end)
            end)

          {parent_ctx.span_id, Task.await(task)}
        end)
      end)

    assert_receive {:exported_trace, %Trace{} = trace, _state}

    assert %Span{} = parent = Trace.get_span(trace, parent_span_id)
    assert %Span{} = child = Trace.get_span(trace, child_span_id)
    assert child.parent_span_id == parent.span_id
    assert Enum.any?(parent.events, &(&1.name == "parent_event"))
    assert Enum.any?(child.events, &(&1.name == "task_event"))
    assert child.attributes == %{task_boundary: true}
    assert AITrace.get_current_context() == nil
  end

  test "trace macro clears process dictionary context after success" do
    assert AITrace.get_current_context() == nil

    result =
      AITrace.trace "macro_cleanup_success" do
        assert %Context{} = AITrace.get_current_context()
        :ok
      end

    assert result == :ok

    assert AITrace.get_current_context() == nil
  end

  test "trace macro restores previous process dictionary context after exception" do
    previous_ctx = Context.new("ambient_trace")
    AITrace.set_current_context(previous_ctx)

    assert_raise RuntimeError, "boom", fn ->
      AITrace.trace "macro_cleanup_error" do
        assert %Context{} = current_ctx = AITrace.get_current_context()
        refute current_ctx == previous_ctx
        raise "boom"
      end
    end

    assert AITrace.get_current_context() == previous_ctx
  end

  test "nested span macro restores parent context after child success and child exception" do
    result =
      AITrace.trace "nested_span_cleanup" do
        trace_ctx = AITrace.get_current_context()

        AITrace.span "parent" do
          parent_ctx = AITrace.get_current_context()
          refute parent_ctx == trace_ctx

          child_result =
            AITrace.span "child_success" do
              child_ctx = AITrace.get_current_context()
              refute child_ctx == parent_ctx
              :ok
            end

          assert child_result == :ok
          assert AITrace.get_current_context() == parent_ctx

          assert_raise RuntimeError, "child boom", fn ->
            AITrace.span "child_failure" do
              raise "child boom"
            end
          end

          assert AITrace.get_current_context() == parent_ctx
          :ok
        end

        assert AITrace.get_current_context() == trace_ctx
        :ok
      end

    assert result == :ok

    assert AITrace.get_current_context() == nil
  end

  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)
end
