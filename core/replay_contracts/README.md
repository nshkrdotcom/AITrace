# AITrace Replay Contracts

Ref-only replay contracts for deterministic trace replay, replay bundles, and
bounded divergence evidence. The package carries no raw prompt, provider,
memory, eval, or secret payloads.

Phase 7 replay evidence carries capture level, persistence profile, store refs,
receipt refs, and debug tap refs as metadata only. Replay bundles may be
retained in memory or marked capture `:off`; neither mode changes provider
effect semantics or exposes raw prompt/provider payload bodies.

## Agent Evidence Export

`AITrace.ReplayContracts.agent_evidence_export/1` validates
`schema://aitrace/agent-evidence-export/v1` receipts for governed agent-turn
evidence. Exports are tied to a ledger ref, authority ref, one or more runtime
receipt refs, a redaction manifest ref, and a payload hash. Sequence coverage is
checked from `ledger_seq_from`, `ledger_seq_to`, and `event_count`; gaps fail
closed before replay bundles are accepted as complete.

`AITrace.Integrations.AgentTurn.export_receipt/1` maps product-safe agent turn
events into the same export contract. The mapper accepts bounded event kinds,
ledger sequence numbers, event refs, and optional runtime receipt refs. Raw
prompts, provider bodies, raw payloads, and secret-bearing fields are rejected at
the mapping boundary.

## Persistence Documentation

See `docs/persistence.md` for tiers, defaults, adapters, unsupported selections, config examples, restart claims, durability claims, debug sidecar behavior, redaction guarantees, migration or preflight behavior, and no-bypass scope when applicable.
