---
title: "Capability probes must answer from the routed subset of the product-side wire table, gated exhaustively"
date: 2026-08-16
category: architecture-patterns
module: truapi-server
problem_type: architecture_pattern
component: tooling
severity: critical
applies_when:
  - "Adding a wire-protocol capability probe or discovery query answered from a generated id table"
  - "Asserting that two tables or maps are the same set by construction"
tags: wire-protocol, capability-probe, codegen, registration-gate, rfc-0027
---

# Capability probes must answer from the routed subset of the wire table, gated exhaustively

## Context

RFC 0027 adds `system.feature_supported(Method { id })`: a product probes a
wire discriminant and the host answers whether the id opens a call. The first
design answered from the generated `WIRE_TABLE` directly, assuming the table
and the dispatcher's registered handler set were "the same set by
construction" — `register()` binds every registrar unconditionally. A review
found the table contains entries the product-facing dispatcher never
registers: `#[wire(host_initiated)]` subscriptions (e.g.
`chat_custom_message_render`) are started by the host and served to the
product, so a product cannot begin a call with their ids. The probe answered
`true` for a host-initiated start id while dispatch dropped the frame — the
probe-then-hang failure RFC 0027 exists to eliminate — with the gate still
green because it sampled only one request id and one unallocated id.

## Guidance

1. When a probe asks "does this id open a call on this build", derive the
   answer from the same table the dispatcher routes from — but only the
   product-callable subset. Host-initiated entries must be excluded. In this
   repository the generator parses `#[wire(host_initiated)]` and emits a
   `host_initiated` flag on every `WireEntry` row; `method_entry_registered`
   answers `false` for those rows. The platform-facing funnel forwards
   `Chain` queries and answers `Method` queries in-core, so no host learns
   wire discriminants.
2. Never assert a table/registration equivalence by sampling a few ids. An
   equivalence claim that protects a guarantee ("advertised answers equal
   routed behavior") must be asserted exhaustively: every one of the 256
   possible ids, both directions, against the live registered request/start
   key set (exposed by a test-only accessor on the dispatcher). A wrong
   answer at any id fails the build.
3. Wire-format invariants belong in commit messages; code comments state the
   current invariant. "Variant index 1; a host that cannot decode it answers
   MalformedFrame" is current state; "appended after Chain so older
   encodings keep their bytes" is history, and the repository forbids
   migration-narrating doc comments.

## Why This Matters

A capability probe is a promise: a caller that probes `true` will send the
frame or begin the call and expects it to be served or rejected, never
silently dropped. Sampling gates pass wrong answers on the ids they do not
sample — the same false confidence the probe itself is meant to prevent.
Exhaustive comparison against the live registration surface turns the
guarantee into a build failure.

## When to Apply

- Any new discovery/probe endpoint whose answer derives from a generated id
  or route table.
- Any equivalence claim ("these collections cannot diverge by construction")
  between a generated table and a live registration map — verify the
  construction, then pin the equivalence with a test that fails rather than
  samples.
- When wire ids extend into host-initiated or host-only channels on a
  product-facing protocol, mark them so callable-id answers exclude them.

## Examples

Probe semantics before/after the fix (simplified):

```rust
// BEFORE: table membership == supported (lies for host-initiated rows).
pub fn method_entry_registered(id: u8) -> bool {
    WIRE_TABLE.iter().any(|entry| match entry.kind {
        Request(ids) => ids.request_id == id,
        Subscription(ids) => ids.start_id == id,
    })
}

// AFTER: host-initiated rows (generator-emitted flag) are never callable.
pub fn method_entry_registered(id: u8) -> bool {
    WIRE_TABLE.iter().any(|entry| match (entry.kind, entry.host_initiated) {
        (Request(ids), _) => ids.request_id == id,
        (Subscription(ids), false) => ids.start_id == id,
        (Subscription(_), true) => false,
    })
}
```

## Related

- docs/rfcs/0027-capability-detection.md — the RFC whose probe semantics this pattern pins