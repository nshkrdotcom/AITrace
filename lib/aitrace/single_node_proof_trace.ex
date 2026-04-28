defmodule AITrace.SingleNodeProofTrace do
  @moduledoc """
  Minimal fixture format for single-node BEAM development proof traces.

  This is a development and StackLab proof handoff format. It is intentionally
  not an authoritative audit, compliance, or production deployment proof.
  """

  @schema_version "aitrace.single_node_proof_trace.v1"

  @required_spans ~w(
    workspace_manifest_validated
    repo_local_ci
    stack_lab_proof
    trace_exported
  )

  @repo_refs ~w(
    repo://nshkrdotcom/ground_plane
    repo://nshkrdotcom/execution_plane
    repo://nshkrdotcom/jido_integration
    repo://nshkrdotcom/citadel
    repo://nshkrdotcom/outer_brain
    repo://nshkrdotcom/mezzanine
    repo://nshkrdotcom/app_kit
    repo://nshkrdotcom/extravaganza
    repo://nshkrdotcom/stack_lab
    repo://nshkrdotcom/AITrace
  )

  @denylist ~w(raw_prompt provider_payload workflow_history secret api_key token)

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec required_spans() :: [String.t()]
  def required_spans, do: @required_spans

  @spec fixture(map() | keyword()) :: map()
  def fixture(attrs \\ %{})

  def fixture(attrs) when is_list(attrs), do: attrs |> Map.new() |> fixture()

  def fixture(attrs) when is_map(attrs) do
    %{
      "schema_version" => @schema_version,
      "proof_class" => "single_node_beam_development",
      "trace_id" => Map.get(attrs, :trace_id, "trace://gn-ten/single-node/dev-fixture"),
      "workspace_ref" => Map.get(attrs, :workspace_ref, "workspace://nshkrdotcom/gn-ten"),
      "node_ref" => Map.get(attrs, :node_ref, "node://single-node/local-beam"),
      "batch_ref" => Map.get(attrs, :batch_ref, "batch://gn-ten/dev-fixture"),
      "repo_refs" => Map.get(attrs, :repo_refs, @repo_refs),
      "spans" => Map.get(attrs, :spans, default_spans()),
      "proof_posture" => proof_posture(),
      "evidence_requirements" => [
        "repo_local_ci_receipts",
        "stack_lab_proof_matrix_entry",
        "trace_export_receipt"
      ],
      "not_proven" => [
        "production_deployment",
        "multi_node_failover",
        "authoritative_audit_chain",
        "compliance_export"
      ]
    }
  end

  @spec validate(map()) :: :ok | {:error, [term()]}
  def validate(%{} = fixture) do
    failures =
      []
      |> require_equal(:schema_version, fixture["schema_version"], @schema_version)
      |> require_present(:trace_id, fixture["trace_id"])
      |> require_present(:workspace_ref, fixture["workspace_ref"])
      |> require_present(:node_ref, fixture["node_ref"])
      |> require_required_spans(fixture["spans"])
      |> require_safe_proof_posture(fixture["proof_posture"])
      |> reject_denied_public_fields(fixture)

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate(_fixture), do: {:error, [:invalid_fixture]}

  defp default_spans do
    Enum.map(@required_spans, fn name ->
      %{
        "name" => name,
        "status" => "pass",
        "attributes" => %{
          "workspace_ref" => "workspace://nshkrdotcom/gn-ten",
          "proof_surface" => "single_node_beam"
        }
      }
    end)
  end

  defp proof_posture do
    %{
      "authoritative_audit?" => false,
      "production_deployment_proven?" => false,
      "safe_action" => "use_as_development_trace_fixture"
    }
  end

  defp require_equal(failures, _field, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, field, actual, expected) do
    [{:mismatch, field, expected, actual} | failures]
  end

  defp require_present(failures, field, value) when is_binary(value) do
    if String.trim(value) == "", do: [{:missing, field} | failures], else: failures
  end

  defp require_present(failures, field, _value), do: [{:missing, field} | failures]

  defp require_required_spans(failures, spans) when is_list(spans) do
    present_names = MapSet.new(Enum.map(spans, & &1["name"]))

    missing =
      @required_spans
      |> Enum.reject(&MapSet.member?(present_names, &1))

    case missing do
      [] -> failures
      missing -> [{:missing_spans, missing} | failures]
    end
  end

  defp require_required_spans(failures, _spans), do: [{:invalid, :spans} | failures]

  defp require_safe_proof_posture(failures, %{} = posture) do
    unsafe? =
      posture["authoritative_audit?"] == true or
        posture["production_deployment_proven?"] == true or
        posture["safe_action"] != "use_as_development_trace_fixture"

    if unsafe?, do: [{:unsafe_proof_posture, posture} | failures], else: failures
  end

  defp require_safe_proof_posture(failures, _posture), do: [{:invalid, :proof_posture} | failures]

  defp reject_denied_public_fields(failures, fixture) do
    encoded = Jason.encode!(fixture)

    hits = Enum.filter(@denylist, &String.contains?(encoded, &1))

    case hits do
      [] -> failures
      hits -> [{:denied_public_fields, hits} | failures]
    end
  end
end
