defmodule AITrace.NSHKR.ExportTransportTest do
  use ExUnit.Case, async: true

  alias AITrace.NSHKR.ExportTransport

  defmodule DirectTarget do
    def export_trace(request, opts) do
      {:ok, %{"mode" => "direct", "request" => request, "timeout" => opts[:timeout]}}
    end

    def read_export(ref), do: {:ok, %{"mode" => "direct", "ref" => ref}}
  end

  test "direct transport calls an explicitly supplied AITrace facade" do
    assert {:ok, result} =
             ExportTransport.Direct.export_trace(%{"trace_ref" => "trace://one"},
               target: DirectTarget,
               timeout: 50
             )

    assert result["mode"] == "direct"
    assert result["timeout"] == 50
  end

  test "distributed transport calls an explicitly supplied AITrace facade" do
    assert {:ok, result} =
             ExportTransport.Distributed.export_trace(%{"trace_ref" => "trace://one"},
               node: Node.self(),
               facade_module: DirectTarget,
               timeout: 1_000
             )

    assert result["mode"] == "direct"
  end

  test "fixture transport provides deterministic export evidence" do
    assert {:ok, result} = ExportTransport.Fixture.export_trace(%{}, [])
    assert result["export_ref"] == "trace://fixture/export"
  end

  test "runtime deps select an AITrace export transport explicitly" do
    assert {:ok, deps} =
             ExportTransport.RuntimeDeps.new(
               transport: ExportTransport.Fixture,
               transport_opts: [export_trace: {:ok, %{"status" => "exported"}}]
             )

    assert {:ok, %{"status" => "exported"}} = ExportTransport.RuntimeDeps.export_trace(deps, %{})
  end
end
