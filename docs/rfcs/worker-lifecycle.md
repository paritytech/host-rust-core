---
title: "Worker Lifecycle"
owner: "@johnthecat"
status: draft
---

# RFC — Worker Lifecycle

## Summary

A product has one worker. The host runs it while a reference to it is held and may stop it when none is. Modality work
takes a reference for as long as it is on screen or in flight. Acknowledging a product grants one short run so the
worker can set up before anything references it.

## Motivation

The [Product Manifest Format](product-manifest.md) defines the worker as the product's single background process and
does not say when it runs. A worker that runs for the life of the host is a signing-capable process per product running
unobserved. A worker that runs only with the product's app view cannot serve a chat room while the view is closed. Every
modality that calls a worker needs the same rule.

### Requirements

1. **Single.** A product has one worker process, however many modalities call it.
2. **Demand-driven.** The worker runs only while the host has work that only the worker can do.
3. **Stoppable.** The host may stop an unreferenced worker at any time and the product keeps working.
4. **Setup.** An acknowledged product gets a run before anything calls its worker.
5. **Additive.** No wire change; the host starts and stops the worker executable.

## Approach

The host keeps one reference count per product worker. The first reference starts the worker. When the count returns to
zero the host may stop it. Products do not ask for a worker to run.

The design has three parts:

- **References**: what holds the worker.
- **Acknowledgement grant**: the one run without a reference.
- **Product rules**: what a worker must tolerate.

### References

A reference is held for exactly as long as its work is on screen or in flight. Several references of one product hold
one worker. A modality names its holders in its own RFC. App and Widget executables hold no reference; their lifetime is
their screen.

Reference holders, by modality:

| Holder  | Held while                                                                                            |
| ------- | ----------------------------------------------------------------------------------------------------- |
| Chat    | A room the product serves is on screen, or a message addressed to the product is in flight.           |
| Pocket  | An artifact the product contributed is on screen.                                                     |
| Funding | The product is the selected provider of a funding flow, from selection until the flow settles.        |
| Input   | An input surface is open, or a `Custom` candidate is on screen ([Input Modality](input-modality.md)). |

### Acknowledgement grant

When the host acknowledges a product, it takes a time-limited reference on the worker. Acknowledgement may be a pin, an
addition to widgets or pocket, or the adoption of a new deployment of an acknowledged product. Nothing calls the worker
during the grant. The window is host policy, and the host releases the reference whether or not the worker is done, so
setup is idempotent and resumes on the next start.

### Product rules

- A worker tolerates being stopped whenever nothing references it, including mid-setup and while its output is on
  screen. State that must survive goes through host storage.
- A worker does not read being started as user intent.
- A worker does no background work of its own. Proactive wakeups are the host's to schedule and are a separate RFC.

Nothing crosses the wire. The worker learns it is needed by receiving a modality call.

## Trade-offs

- Setup that outlives the grant completes on a later start.
- A worker may start and stop several times in one pocket scroll. The host may keep an unreferenced worker warm; the
  product may not rely on it.
- Considered and dropped: an always-on worker, a start per call without counting, one worker per modality.

## Open questions

- Whether a worker is told what started it, a grant or a reference. Nothing distinguishes the two from inside the
  worker.
