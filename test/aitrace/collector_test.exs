defmodule AITrace.CollectorTest do
  use ExUnit.Case, async: false

  alias AITrace.{Collector, Span}

  setup do
    assert :ok = clear_collector()

    on_exit(fn ->
      ensure_collector_started()
      clear_collector()
    end)

    :ok
  end

  test "collector starts supervised owner infrastructure" do
    assert is_pid(Process.whereis(Collector))
    assert is_pid(Process.whereis(Collector.Supervisor))
    assert is_pid(Process.whereis(Collector.Registry))
  end

  test "traces are partitioned into separate supervised owners" do
    trace_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    trace_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    assert %{trace_id: ^trace_a} = Collector.new_trace(trace_a)
    assert %{trace_id: ^trace_b} = Collector.new_trace(trace_b)

    pid_a = Collector.owner_pid(trace_a)
    pid_b = Collector.owner_pid(trace_b)
    assert is_pid(pid_a)
    assert is_pid(pid_b)
    refute pid_a == pid_b

    assert :ok = Collector.add_span(trace_a, Span.new("a-only"))

    assert [%Span{name: "a-only"}] = Collector.get_trace(trace_a).spans
    assert [] = Collector.get_trace(trace_b).spans
  end

  test "collector enforces per-trace span capacity and records drops" do
    trace_id = "cccccccccccccccccccccccccccccccc"
    assert %{trace_id: ^trace_id} = Collector.new_trace(trace_id, max_spans_per_trace: 1)

    assert :ok = Collector.add_span(trace_id, Span.new("first"))

    assert {:error, %{code: :capacity_exceeded, dropped_spans: 1, max_spans: 1}} =
             Collector.add_span(trace_id, Span.new("second"))

    assert [%Span{name: "first"}] = Collector.get_trace(trace_id).spans
    assert %{dropped_spans: 1, max_spans: 1, span_count: 1} = Collector.stats(trace_id)
  end

  test "abnormal owner crash restarts owner with non-authoritative in-memory state lost" do
    trace_id = "dddddddddddddddddddddddddddddddd"
    assert %{trace_id: ^trace_id} = Collector.new_trace(trace_id)
    assert :ok = Collector.add_span(trace_id, Span.new("before-crash"))

    old_pid = Collector.owner_pid(trace_id)
    ref = Process.monitor(old_pid)
    Process.exit(old_pid, :kill)

    assert_receive {:DOWN, ^ref, :process, ^old_pid, :killed}

    new_pid = wait_for_restarted_owner(trace_id, old_pid)
    assert is_pid(new_pid)
    refute new_pid == old_pid
    assert [] = Collector.get_trace(trace_id).spans
    assert Collector.authoritative_evidence?() == false
  end

  test "clear requires supervised collector startup and does not auto-start" do
    assert :ok = Supervisor.terminate_child(AITrace.Supervisor, Collector)
    assert Process.whereis(Collector) == nil

    assert {:error, :collector_not_started} = Collector.clear()
    assert Process.whereis(Collector) == nil

    assert {:ok, _pid} = Supervisor.restart_child(AITrace.Supervisor, Collector)
    assert is_pid(Process.whereis(Collector))
  end

  defp clear_collector do
    case Collector.clear() do
      :ok -> :ok
      {:error, :collector_not_started} -> :ok
    end
  end

  defp ensure_collector_started do
    case Process.whereis(Collector) do
      nil -> Supervisor.restart_child(AITrace.Supervisor, Collector)
      _pid -> :ok
    end
  end

  defp wait_for_restarted_owner(trace_id, old_pid, attempts_left \\ 50)

  defp wait_for_restarted_owner(_trace_id, _old_pid, 0), do: nil

  defp wait_for_restarted_owner(trace_id, old_pid, attempts_left) do
    case Collector.owner_pid(trace_id) do
      pid when is_pid(pid) and pid != old_pid ->
        pid

      _other ->
        receive do
        after
          10 -> wait_for_restarted_owner(trace_id, old_pid, attempts_left - 1)
        end
    end
  end
end
