# AITrace Replay Contracts

Ref-only replay contracts for deterministic trace replay, replay bundles, and
bounded divergence evidence. The package carries no raw prompt, provider,
memory, eval, or secret payloads.

Phase 7 replay evidence carries capture level, persistence profile, store refs,
receipt refs, and debug tap refs as metadata only. Replay bundles may be
retained in memory or marked capture `:off`; neither mode changes provider
effect semantics or exposes raw prompt/provider payload bodies.

## Persistence Documentation

See `docs/persistence.md` for tiers, defaults, adapters, unsupported selections, config examples, restart claims, durability claims, debug sidecar behavior, redaction guarantees, migration or preflight behavior, and no-bypass scope when applicable.
