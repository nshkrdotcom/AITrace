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
- AITrace is not in the Weld consumer set. Do not add a Weld dependency, Weld
  task, or Weld Credo check as part of Phase 2 cleanup.

## Dependency Sources

- Cross-repo dependency selection belongs in
  `build_support/dependency_sources.config.exs` and is consumed through the
  canonical `build_support/dependency_sources.exs` helper.
- Machine-local dependency overrides belong in `.dependency_sources.local.exs`.
  Keep that file untracked.
- Dependency source selection must not read environment variables.

## Runtime Environment

- Runtime application code under `lib/**` must not call direct OS environment
  APIs such as `System.get_env/1`, `System.fetch_env/1`,
  `System.fetch_env!/1`, `System.put_env/2`, `System.delete_env/1`, or
  `System.get_env/0`.
- Deployment environment reads belong at OTP boot boundaries such as
  `config/runtime.exs` or a `Config.Provider`. Runtime modules should receive
  explicit options or materialized application config.

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
