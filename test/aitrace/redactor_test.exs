defmodule AITrace.RedactorTest do
  use ExUnit.Case, async: true

  test "redacts sensitive keys recursively" do
    payload = %{nested: [%{api_key: "secret"}], authorization: "Bearer token"}

    assert AITrace.Redactor.redact(payload, :redacted) == %{
             nested: [%{api_key: "<redacted>"}],
             authorization: "<redacted>"
           }
  end

  test "redacts exact materialized values" do
    assert AITrace.Redactor.redact_values(%{message: "token=abc123"}, ["abc123"]) == %{
             message: "token=<redacted>"
           }
  end
end
