# AITrace Replay Engine

Deterministic replay execution for archived or live AITrace traces. Replay
mode reconstructs trace spans, compares outcomes, emits bounded divergence
refs, and never invokes live provider effects.

Phase 7 replay execution consumes redacted capture posture from AITrace replay
contracts. The engine treats persistence posture as evidence, not authority:
memory/default and capture `:off` profiles do not require durable substrates
and cannot rehydrate raw provider or prompt bodies.
