defmodule AITrace.RemoteFacade.EvidenceTest do
  use ExUnit.Case, async: true

  alias AITrace.NSHKR.ExportTransport
  alias AITrace.RemoteFacade.Evidence

  test "declares owner-defined evidence group" do
    assert Evidence.owner_group() == {Evidence, :evidence}
  end

  test "exports bounded evidence through configured transport" do
    assert {:ok, result} =
             Evidence.export_trace(valid_envelope(),
               transport: ExportTransport.Fixture,
               transport_opts: [export_trace: {:ok, %{"export_ref" => "trace-export://one"}}]
             )

    assert result["export_ref"] == "trace-export://one"
  end

  test "rejects missing trace ref before transport" do
    assert {:error, %{"code" => "invalid_envelope", "missing_field" => "trace_ref"}} =
             valid_envelope()
             |> Map.delete("trace_ref")
             |> Evidence.export_trace(transport: ExportTransport.Fixture)
  end

  test "readback delegates through configured transport" do
    assert {:ok, result} =
             Evidence.read_export("trace-export://one",
               transport: ExportTransport.Fixture,
               transport_opts: [read_export: {:ok, %{"status" => "exported"}}]
             )

    assert result["status"] == "exported"
  end

  defp valid_envelope do
    %{
      "schema_ref" => "aitrace.export.v1",
      "tenant_ref" => "tenant://one",
      "correlation_ref" => "corr://one",
      "idempotency_key" => "idem://one",
      "trace_ref" => "trace://one",
      "redaction_class" => "tenant_sensitive"
    }
  end
end
