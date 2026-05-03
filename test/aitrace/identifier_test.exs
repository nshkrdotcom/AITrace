defmodule AITrace.IdentifierTest do
  use ExUnit.Case, async: true

  alias AITrace.Identifier

  test "generates lower hex trace and span ids from one owner policy" do
    trace_id = Identifier.generate(:trace)
    span_id = Identifier.generate(:span)

    assert lower_hex_id?(trace_id)
    assert lower_hex_id?(span_id)

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

  defp lower_hex_id?(id) do
    byte_size(id) == 32 and
      id
      |> :binary.bin_to_list()
      |> Enum.all?(fn byte -> byte in ?0..?9 or byte in ?a..?f end)
  end
end
