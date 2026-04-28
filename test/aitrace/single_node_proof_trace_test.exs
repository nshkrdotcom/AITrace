defmodule AITrace.SingleNodeProofTraceTest do
  use ExUnit.Case, async: true

  alias AITrace.SingleNodeProofTrace

  test "builds a deterministic single-node proof trace fixture" do
    fixture = SingleNodeProofTrace.fixture()

    assert fixture["schema_version"] == "aitrace.single_node_proof_trace.v1"
    assert fixture["proof_class"] == "single_node_beam_development"
    assert fixture["workspace_ref"] == "workspace://nshkrdotcom/gn-ten"
    assert length(fixture["repo_refs"]) == 10
    assert Enum.map(fixture["spans"], & &1["name"]) == SingleNodeProofTrace.required_spans()
    assert fixture["proof_posture"]["authoritative_audit?"] == false
    assert fixture["proof_posture"]["production_deployment_proven?"] == false
    assert :ok = SingleNodeProofTrace.validate(fixture)
  end

  test "rejects missing required spans" do
    fixture = SingleNodeProofTrace.fixture(%{spans: []})

    assert {:error, failures} = SingleNodeProofTrace.validate(fixture)
    assert {:missing_spans, SingleNodeProofTrace.required_spans()} in failures
  end

  test "rejects unsafe proof posture" do
    fixture =
      SingleNodeProofTrace.fixture()
      |> put_in(["proof_posture", "authoritative_audit?"], true)

    assert {:error, failures} = SingleNodeProofTrace.validate(fixture)
    assert Enum.any?(failures, &match?({:unsafe_proof_posture, _}, &1))
  end

  test "rejects denied public fields" do
    fixture = Map.put(SingleNodeProofTrace.fixture(), "raw_prompt", "do the unsafe thing")

    assert {:error, failures} = SingleNodeProofTrace.validate(fixture)
    assert {:denied_public_fields, ["raw_prompt"]} in failures
  end
end
