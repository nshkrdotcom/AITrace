defmodule AITrace.IdentifierTest do
  use ExUnit.Case, async: true

  alias AITrace.Identifier

  test "generates lower hex trace and span ids from one owner policy" do
    trace_id = Identifier.generate(:trace)
    span_id = Identifier.generate(:span)

    assert trace_id =~ ~r/\A[0-9a-f]{32}\z/
    assert span_id =~ ~r/\A[0-9a-f]{32}\z/

    assert Identifier.source!(:trace, trace_id, :aitrace_generated).kind ==
             :aitrace_generated

    assert Identifier.source!(:span, span_id, :aitrace_generated).kind ==
             :aitrace_generated
  end

  test "classifies caller supplied ids as bounded external aliases" do
    source = Identifier.source!(:trace, "external.trace-1", :external_alias)

    assert source.kind == :external_alias
    assert source.id_type == :trace
    assert source.validation == "bounded_external_alias"
  end

  test "rejects malformed imported ids before proof use" do
    assert_raise ArgumentError, fn ->
      Identifier.source!(:trace, "bad trace id", :external_alias)
    end

    assert_raise ArgumentError, fn ->
      Identifier.source!(:span, "", :external_alias)
    end
  end
end
