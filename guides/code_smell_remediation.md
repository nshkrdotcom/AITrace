# AITrace Code Smell Remediation

This guide records the repo-local implementation posture after the GN-TEN code
smell remediation pass.

## What Changed

- Explicit context APIs now exist for trace/span lifecycle and event/attribute
  mutation; macros are convenience wrappers with `try/after` cleanup.
- Export profiles are captured on trace context so governed exports do not
  depend on ambient application env at finish time.
- Collector state is partitioned into supervised trace owners with capacity
  telemetry and no auto-starting `clear/0`.
- File exporter writes artifacts and evidence through temporary files, sync,
  and rename, and can verify missing artifact/evidence pairs.
- Replay engine responsibilities are split into request runner, lineage
  replay runner, lineage sorter, projection reducer, and divergence reporter.
- Runtime identity is supervised by `AITrace.RuntimeIdentity`; AITrace no
  longer uses `:persistent_term`.

## Maintainer Rules

- AITrace observes and exports trace evidence. It does not own authorization,
  durable audit truth, product completion, or lower execution.
- Governed callers should pass explicit contexts and export profiles.
- Collector state is non-authoritative in-memory working state; authoritative
  proof requires exported receipts linked by the owning higher layer.

## QC

Use the repo root gate:

```bash
mix deps.get && mix format --check-formatted && mix compile --warnings-as-errors && mix test && mix credo --strict && mix dialyzer --format short && mix docs
```
