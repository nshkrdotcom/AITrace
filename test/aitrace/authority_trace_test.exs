defmodule AITrace.AuthorityTraceTest do
  use ExUnit.Case, async: true

  alias AITrace.AuthorityTrace

  test "builds ref-only authority trace events" do
    assert {:ok, event} = AuthorityTrace.event(valid_attrs())

    assert event.event_name == "authority.provider_dispatch"
    assert event.authority_packet_ref == "authority-packet://tenant-1/packet-1"
    assert event.provider_account_ref == "provider-account://tenant-1/claude/main"
    assert event.credential_lease_ref == "credential-lease://tenant-1/claude/lease-1"
    assert event.redaction_policy_ref == "redaction-policy://tenant-1/authority"
    assert event.provider_account_status == :asserted
    assert event.identity_introspection_limit == :ref_only
    assert event.raw_material_present? == false
  end

  test "rejects missing refs before trace export" do
    assert {:error, {:missing_required_refs, missing}} =
             valid_attrs()
             |> Map.delete(:authority_packet_ref)
             |> Map.delete(:target_ref)
             |> AuthorityTrace.event()

    assert missing == [:authority_packet_ref, :target_ref]
  end

  test "rejects raw secrets and provider payloads from authority trace events" do
    assert {:error, {:forbidden_trace_material, forbidden}} =
             valid_attrs()
             |> Map.put(:authorization_header, "Bearer secret")
             |> Map.put(:provider_payload, %{"token" => "secret"})
             |> Map.put(:raw_token, "secret")
             |> AuthorityTrace.event()

    assert forbidden == [:authorization_header, :provider_payload, :raw_token]
  end

  test "exports bounded trace attributes with refs and no raw material" do
    assert {:ok, event} = AuthorityTrace.event(valid_attrs())

    attrs = AuthorityTrace.export_attributes(event)

    assert attrs["authority_packet_ref"] == "authority-packet://tenant-1/packet-1"
    assert attrs["connector_binding_ref"] == "connector-binding://tenant-1/claude/default"
    assert attrs["requested_operation"] == "agent.run"
    assert attrs["admission_state"] == :admitted
    assert attrs["proof_refs"] == ["proof-artifact://tenant-1/authority/1"]
    assert attrs["scanner_refs"] == ["scanner://stack-lab/no-bypass/1"]
    assert attrs["redaction_class"] == "ref_only"
    assert attrs["overflow_safe_action"] == "drop_raw_material_keep_ref"
    assert attrs["raw_material_present?"] == false
    assert attrs["provider_account_status"] == :asserted
    assert attrs["identity_introspection_limit"] == :ref_only
    refute inspect(attrs) =~ "secret"
    refute Map.has_key?(attrs, "provider_payload")
  end

  test "bounds provider-account identity status and introspection export" do
    assert {:ok, event} =
             valid_attrs()
             |> Map.put(:provider_account_status, "rotated")
             |> Map.put(:identity_introspection_limit, "redacted_summary")
             |> AuthorityTrace.event()

    attrs = AuthorityTrace.export_attributes(event)
    assert attrs["provider_account_status"] == :rotated
    assert attrs["identity_introspection_limit"] == :redacted_summary

    assert {:error, {:invalid_trace_enum, :provider_account_status, :stale, allowed_statuses}} =
             valid_attrs()
             |> Map.put(:provider_account_status, :stale)
             |> AuthorityTrace.event()

    assert allowed_statuses == AuthorityTrace.provider_account_statuses()

    assert {:error,
            {:invalid_trace_enum, :identity_introspection_limit, :full_payload, allowed_limits}} =
             valid_attrs()
             |> Map.put(:identity_introspection_limit, :full_payload)
             |> AuthorityTrace.event()

    assert allowed_limits == AuthorityTrace.identity_introspection_limits()
  end

  test "requires connector binding and admission projection refs for authority export" do
    assert {:error, {:missing_required_refs, missing}} =
             valid_attrs()
             |> Map.delete(:connector_binding_ref)
             |> Map.delete(:requested_operation)
             |> Map.delete(:admission_state)
             |> AuthorityTrace.event()

    assert missing == [:connector_binding_ref, :requested_operation, :admission_state]
  end

  defp valid_attrs do
    %{
      event_name: "authority.provider_dispatch",
      authority_packet_ref: "authority-packet://tenant-1/packet-1",
      system_authorization_ref: "system-authority://tenant-1/decision-1",
      provider_family: "claude",
      provider_account_ref: "provider-account://tenant-1/claude/main",
      connector_instance_ref: "connector-instance://tenant-1/claude/default",
      connector_binding_ref: "connector-binding://tenant-1/claude/default",
      credential_handle_ref: "credential-handle://tenant-1/claude/handle-1",
      credential_lease_ref: "credential-lease://tenant-1/claude/lease-1",
      native_auth_assertion_ref: "native-auth-assertion://tenant-1/claude/1",
      target_ref: "target://tenant-1/local-process/1",
      attach_grant_ref: "attach-grant://tenant-1/local-process/1",
      operation_policy_ref: "operation-policy://tenant-1/claude/chat",
      requested_operation: "agent.run",
      admission_state: :admitted,
      rejection_reason: nil,
      redaction_policy_ref: "redaction-policy://tenant-1/authority",
      proof_artifact_ref: "proof-artifact://tenant-1/authority/1",
      proof_refs: ["proof-artifact://tenant-1/authority/1"],
      scanner_refs: ["scanner://stack-lab/no-bypass/1"],
      redaction_class: "ref_only",
      trace_ref: "trace://tenant-1/authority/1",
      provider_account_status: :asserted,
      provider_account_evidence_ref: "evidence://tenant-1/provider-account/1",
      identity_introspection_limit: :ref_only
    }
  end
end
