---
title: "Worker Lifecycle"
owner: "@johnthecat"
status: draft
---

# RFC — Worker Lifecycle

## Summary

A product has one worker. The host runs it while a reference to it is held and may stop it when none is. Modality work
takes a reference for as long as it is on screen or in flight. Acknowledging a product, by pinning it or adding it to
widgets or pocket, grants one short run so the worker can set up before anything references it.

## Motivation

The [Product Manifest Format](product-manifest.md) defines the worker as the product's single background process and
does not say when it runs. A worker that runs only with the product's app view cannot serve a chat room while the view
is closed, and every modality that calls a worker needs one rule for when it runs.

### Requirements

1. **Single.** A product has one worker process, however many modalities call it.
2. **Demand-driven.** The worker runs only while the host has work that only the worker can do.
3. **Stoppable.** The host may stop an unreferenced worker at any time and the product keeps working.
4. **Setup.** An acknowledged product gets a run before anything calls its worker.
5. **Additive.** Nothing is added to the TrUAPI protocol.

## Approach

The host keeps one reference count per product worker. The first reference starts the worker. When the count returns to
zero the host may stop it. Products do not ask for a worker to run: the host starts and stops the worker executable, and
the worker learns it is needed by receiving a modality call.

The design has three parts:

- **References**: what holds the worker.
- **Acknowledgement grant**: the one run without a reference.
- **Stopping**: when the host stops a worker.

### References

A reference is held for exactly as long as its work is on screen or in flight. Several references of one product hold
one worker: a pocket artifact and an input surface over it are two references on the same worker. A modality names its
holders in its own RFC. App and Widget executables hold no reference; their lifetime is their screen.

Reference holders, by modality:

| Holder  | Held while                                                                                               |
| ------- | -------------------------------------------------------------------------------------------------------- |
| Chat    | A room the product serves is on screen, or a message addressed to the product is in flight.              |
| Pocket  | An artifact the product contributed is on screen.                                                        |
| Funding | A funding flow with the product as selected provider is in flight, from selection until it settles.      |
| Input   | An input round is in flight, or a `Custom` candidate is on screen ([Input Modality](input-modality.md)). |

### Acknowledgement grant

When the host acknowledges a product, or adopts a new deployment of an acknowledged product, it takes a time-limited
reference on the worker. Nothing calls the worker during the grant; the product uses it for setup such as registering
its chat bot. The window is host policy, and the host releases the reference whether or not the worker is done, so setup
is idempotent and resumes on the next start.

### Stopping

- The host may stop a worker whenever nothing references it, including mid-setup and while its output is on screen, so
  state that must survive goes through host storage.
- The host starts a worker when a reference forms, not when the user acts on the product, so a start is not user intent.
- The host runs a worker only while it is referenced, so a worker has no way to do background work of its own. Scheduled
  wakeups are out of scope.

## Trade-offs

- A worker may start and stop several times in one pocket scroll. The host may keep an unreferenced worker warm; the
  product may not rely on it.
- Considered and dropped: an always-on worker, a start per call without counting, one worker per modality.

## Open questions

- Whether a worker is told what started it, a grant or a reference. Nothing distinguishes the two from inside the
  worker.
