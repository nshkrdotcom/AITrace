# AITrace Replay Engine

Deterministic replay execution for archived or live AITrace traces. Replay
mode reconstructs trace spans, compares outcomes, emits bounded divergence
refs, and never invokes live provider effects.

Phase 7 replay execution consumes redacted capture posture from AITrace replay
contracts. The engine treats persistence posture as evidence, not authority:
memory/default and capture `:off` profiles do not require durable substrates
and cannot rehydrate raw provider or prompt bodies.

## Persistence Documentation

See `docs/persistence.md` for tiers, defaults, adapters, unsupported selections, config examples, restart claims, durability claims, debug sidecar behavior, redaction guarantees, migration or preflight behavior, and no-bypass scope when applicable.
