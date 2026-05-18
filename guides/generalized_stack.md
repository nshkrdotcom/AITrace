# AITrace Generalized Stack Boundary

## Responsibility

AITrace owns trace, span, event, replay, export, and redaction evidence
contracts. It helps the platform prove what an instrumented path emitted and
what can be replayed from those emitted facts.

AITrace does not own product acceptance, durable workflow truth, authority
truth, connector execution, credential leases, or lower runtime state. Those
claims are owned by Extravaganza, Mezzanine, Citadel, Jido Integration,
Execution Plane, and StackLab, then linked to AITrace refs when replay evidence
exists.

## Public Interfaces

The active repo surface includes:

- root trace/span/event APIs for Elixir callers;
- explicit export behavior with bounded attributes and redaction;
- `core/replay_contracts` for replay bundle contracts;
- `core/replay_engine` for deterministic replay over exported trace facts.

Governed callers must pass explicit exporters and evidence refs. Ambient
application env may be used for standalone tracing, but not for governed
release evidence.

## Extravaganza Cutover Proof

The current Extravaganza cutover proof returns route evidence that includes
trace refs. The headless product commands currently report
`trace_replay.status: not_emitted`, which is an explicit non-claim: the product
path has route and receipt evidence, but it has not exported a replay bundle
through AITrace for that command.

Future replay claims require Mezzanine or the product-owned path to emit the
right trace events, spans, export receipts, and replay bundle refs. AITrace can
only reconstruct facts that were emitted to it; it must not infer authority,
lifecycle, or connector truth from absent events.

## Dependency Rules

Allowed dependencies:

- stable contracts for replay bundles, export receipts, and redacted evidence;
- StackLab proof fixtures that join AITrace refs to release claims;
- owning-repo refs supplied explicitly by governed callers.

Forbidden dependencies:

- product-specific defaults inside generic replay code;
- authority or credential decisions inside trace exporters;
- raw prompt, provider payload, webhook body, secret, or oversize payload
  capture in public replay receipts;
- ambient exporter selection for governed evidence.

## Migration And Cleanup Ownership

AITrace cleanup work removes ambiguous replay claims, unbounded attribute
capture, ambient governed exporters, stale proof fixtures, and receipts that do
not state whether replay evidence was emitted, absent, or outside the current
claim.
