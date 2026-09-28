# @parity/truapi-provider

## 0.2.2

### Patch Changes

- a8fd3a0: The browser bundle is 4.25 MiB raw and 0.94 MiB brotli, down from 5.31 MiB and 2.01 MiB. smoldot's secp256k1
  multiplication tables are built the first time a runtime call uses a secp256k1 host function, in about 10 ms, instead
  of shipping as 1 MiB of precomputed points.

## 0.2.1

### Patch Changes

- a0387c9: The embedded light client answers `statement_subscribeStatement` the way a full node does: the subscription
  id is followed immediately by a snapshot batch carrying `remaining: 0`, empty when nothing matches, so a client that
  waits for the end of the replay before issuing its first query resolves rather than hanging. Live notifications still
  omit `remaining`, keeping a snapshot distinguishable from a gossiped statement.

## 0.2.0

### Minor Changes

- 087bdf6: The embedded light client holds at most 32 connections at once. A `connect` past that is refused with "the
  light client already holds 32 connections" instead of adding another chain, request queue, response stream and frame
  channel that nothing will release. Closing a connection hands its slot back.

  The ceiling is a backstop against connections a consumer never closes, not a budget to spend: the bundled catalog
  resolves eight chains, so one reused connection per chain stays well under it.
