# AITrace QC And Operations

AITrace owns bounded trace export, replay bundle, and evidence receipt behavior.
It does not grant authority, execute models, or compile context.

## Local QC

```bash
mix ci
```

## Stack Proof Role

StackLab consumes AITrace receipts to prove that context, routing, model
invocation, optimization, and replay paths carry trace refs without exposing
raw prompt, memory, provider payload, credential, or private tool output.

## Operational Rules

- keep export receipts bounded and redacted;
- include node/source evidence only as portable refs;
- treat replay bundles as governed artifacts with explicit persistence posture;
- never use process dictionary trace state as a distributed contract.
