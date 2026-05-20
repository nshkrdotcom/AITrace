defmodule AITrace.RuntimeIdentityTest do
  use ExUnit.Case, async: false

  alias AITrace.{Clock, Context, RuntimeIdentity}

  test "boot runtime identity is stable and used by the default clock domain" do
    first = RuntimeIdentity.snapshot()
    second = RuntimeIdentity.snapshot()

    assert first == second
    assert first.runtime_id == Clock.clock_domain().runtime_id
    assert first.node == Clock.clock_domain().node
  end

  test "test support can start a scoped runtime identity without global mutation" do
    name = :"runtime_identity_#{System.unique_integer([:positive])}"

    start_supervised!({RuntimeIdentity, name: name, runtime_id: "runtime://test-scope"})

    assert %{runtime_id: "runtime://test-scope"} = RuntimeIdentity.snapshot(name)
    assert Clock.clock_domain(runtime_identity: name).runtime_id == "runtime://test-scope"
    refute Clock.clock_domain().runtime_id == "runtime://test-scope"
  end

  test "new explicit contexts carry the boot runtime identity snapshot" do
    snapshot = RuntimeIdentity.snapshot()
    ctx = Context.new()

    assert ctx.runtime_identity == snapshot
  end
end
