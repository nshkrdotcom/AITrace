# AITrace Onboarding

Read `AGENTS.md` first; the managed gn-ten section is the repo contract.
`CLAUDE.md` must stay a one-line compatibility shim containing `@AGENTS.md`.

## Owns

Trace model, spans/events, exporters, evidence receipts, trace references, and
execution-cinema data shapes.

## Does Not Own

Governance decisions, durable audit truth, execution, product behavior,
credential handling, or provider-specific semantics.

## First Task

```bash
cd /home/home/p/g/n/AITrace
mix deps.get && mix format --check-formatted && mix compile --warnings-as-errors && mix test && mix credo --strict && mix dialyzer --format short && mix docs
cd /home/home/p/g/n/stack_lab
mix gn_ten.plan --repo AITrace
```

## Proofs

StackLab owns assembled proof. Use `/home/home/p/g/n/stack_lab/proof_matrix.yml`
and `/home/home/p/g/n/stack_lab/docs/gn_ten_proof_matrix.md`.

## Common Changes

Trace evidence is not audit truth. Keep trace posture explicit and let
Mezzanine/Citadel own authority and audit semantics.
