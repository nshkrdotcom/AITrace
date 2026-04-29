# AGENTS.md

## Onboarding

Read `ONBOARDING.md` first for the repo's one-screen ownership, first command,
and proof path.

<!-- gn-ten:repo-agent:start repo=AITrace source_sha=ab276c0640772b73065ab12bf05d77be51f1bb67 -->
# AITrace Agent Instructions Draft

## Owns

- Trace model.
- Spans and events.
- Exporters.
- Evidence receipts for trace artifacts.
- Execution-cinema data model.

## Does Not Own

- Governance decisions.
- Durable audit truth.
- Execution.
- Product behavior.
- Credential handling.

## Allowed Dependencies

- Minimal serialization and development tooling.
- GroundPlane refs only when they remain generic and optional.

## Forbidden Imports

- Product modules.
- Mezzanine workflow internals.
- Execution Plane runtime internals.
- Provider SDKs for trace semantics.

## Verification

- Equivalent AITrace gate:
  `mix deps.get && mix format --check-formatted && mix compile --warnings-as-errors && mix test && mix credo --strict && mix dialyzer --format short && mix docs`

## Escalation

If evidence needs authority or audit semantics, expose trace refs and let
Mezzanine/Citadel own the authoritative proof.
<!-- gn-ten:repo-agent:end -->
