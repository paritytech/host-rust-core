# Wire Observability and Debug Host

|                    |                                                                                 |
| ------------------ | ------------------------------------------------------------------------------- |
| **Start Date**     | 2026-07-25 |
| **Authors**        | Nidish Ramakrishnan |
| **Implementation** | truapi#295 |
| **Tracking**       | sdk-team#26 |

## Scope

This specifies the contracts a TrUAPI wire debugger and the host tap that feeds it
must satisfy: where the tap may live, what a sink may and may not do, the envelope
and the wire-contract identity carried with it, how frames are correlated, and how
each surface is confined.

It does not specify tuning values, UI layout, or file structure. Where the text
below names a default, it is naming an implementation choice, not a requirement —
a conforming implementation may pick another. **MUST** / **MUST NOT** / **SHOULD**
carry their usual force; everything else is rationale.

## Model

Product↔host TrUAPI traffic is opaque SCALE frames with no Network tab. A tap in
the Rust host core emits every frame as opaque bytes; the debugger — never the
core — correlates them into per-operation traces and decodes them. The host always
dials the debugger, never the reverse. The tap and the decoder do not exist in a
production build.

```
 product ──frames──▶ host core (truapi-server)
                      │  tap: opaque {channelId, dir, bytes}
                      ▼
                   DebugSink ──host dials outward──▶ debugger
                                                     ├ correlate
                                                     └ decode
```

## 1. Tap placement

The tap **MUST** live in the Rust host core (`truapi-server`) behind a sink trait.
It **MUST NOT** exist in `@parity/truapi` (the product package) or in the
TypeScript transport, and **MUST NOT** be reachable from the product side.

`truapi-server` has exactly two frame choke points, and every host — web, iOS,
Android, CLI — funnels through them:

| Direction | Choke point | Ordering requirement |
|---|---|---|
| inbound (product → core) | `ProductRuntime::receive_frame()` | taps **before** decode, so a corrupt frame is still observed |
| outbound (core → product) | `FrameSink::emit_frame()`, via `SinkTransport::send()` | delivers to the product **first**, then taps |

That ordering is the operative reading of *in the path, not in the critical path*:
the tap observes every frame, and no frame waits on it.

The conformance test for placement is that the product package is genuinely
untouched — it has no debug seam at all. A seam in the product transport fails it.

## 2. Sink contract

A sink is installed per product channel (`ProductRuntime::set_debug_sink`). It is
unset by default, so a host that never installs one pays nothing and the tap is
inert.

```rust
/// Dev-only sink for host debug events. Unset ⇒ the tap is inert.
pub trait DebugSink: Send + Sync {
    /// Fire-and-forget: must not block the frame path or fail the operation.
    fn emit(&self, event: DebugEvent);
}

#[non_exhaustive] // room for non-frame events (e.g. SSO); adding one is not breaking
pub enum DebugEvent {
    /// `bytes` are the untouched `ProtocolMessage`; the debugger decodes them,
    /// the core never does.
    Frame { channel_id: ChannelId, dir: FrameDirection, bytes: Vec<u8> },
}
```

- **Emit, never wait.** `emit` **MUST NOT** block the frame path and **MUST NOT**
  fail the operation that produced the event. A slow, absent, or crashed debugger
  loses a trace; it **MUST NOT** lose a session.
- **Panic containment.** The two in-path call sites **MUST** contain a panicking
  sink (`catch_unwind`), because a sink may be out-of-repo. A panic there would
  otherwise unwind into a live dispatch.
- **Payload-blind core.** The core **MUST** pass frame bytes through untouched. It
  **MUST NOT** decode, inspect, or redact them.
- **Bounded producer.** A sink that owns a socket **MUST** bound its backlog by
  both count and bytes, and **MUST** report frames it dropped rather than emitting
  a silently short stream.

## 3. Envelope and wire identity

Each tapped frame becomes one envelope:

```
{ channelId, dir, frame }
```

`frame` is the untouched SCALE `ProtocolMessage`. `dir` is **product-vantage**:
`out` = the frame left the product, `in` = it arrived at it. The Rust tap names
directions host-vantage internally and flips them on the way out, so both ends
agree on which way a frame went without either re-deriving it. Over a text
transport, `frame` is base64 so one envelope is one line.

A producer **MUST** stamp a wire-contract identity alongside the envelope: an
envelope version, the coarse codec version, and a **wire schema hash** over every
frame id and its method leg.

The schema hash is the load-bearing one. Frame ids are `u8` discriminants that get
reassigned as the API evolves, so a frame from a host built against a different
contract would otherwise decode to the *wrong* method and the wrong value —
silently, and with a plausible-looking result. Therefore:

- A debugger **MUST** enable the decode path only for a channel whose schema hash
  affirmatively matches its own.
- An absent or mismatched identity **MUST** still group (grouping is payload-blind)
  and **MUST NOT** be trusted to decode. Requiring an affirmative match, rather
  than rejecting known-bad values, is what closes the omit-the-identity bypass.

## 4. Correlation

- **Key.** Traces **MUST** be keyed on `(channelId, requestId)`, not `requestId`
  alone: each host mints its own `p:1`, `p:2`, …, so two hosts collide. The channel
  keeps their operations apart. This `requestId` is the same id product-sdk
  telemetry spans correlate on, so a frame trace and a product span line up with no
  extra plumbing.
- **Role.** A frame's lifecycle role (request / response / start / receive / …)
  **MUST** be resolved as a pure function of its frame id against the wire table,
  at ingest. It is not correlation state and **MUST NOT** be reconstructed from
  observed ordering. Resolving it at ingest is what makes it true for every
  consumer rather than for one view adapter. A vantage with no frame id, and an
  off-table id, resolve to `unknown`.
- **Generations.** A product may recycle a `requestId` for a later, unrelated call.
  When a fresh opener arrives for an id whose current operation already opened, the
  engine **MUST** rotate to a new generation rather than merge two unrelated calls.
- **Malformed frames.** An undecodable frame **MUST** be surfaced as a `malformed`
  sentinel, not dropped, so a trace records the failure instead of going dark.
- **Bounded ids.** Retained id strings **MUST** be length-clamped. Anything that can
  reach the tap could otherwise send 200k-char ids, one copy per frame, while real
  ids are short (`myapp.dot`, `p:1`).

## 5. Retention, and honesty about it

Retention **MUST** be bounded on three axes — retained traces, frames per trace,
and bytes per trace — and every bound **MUST** surface rather than misreport:

- Whole-operation evictions **MUST** be counted, so a session that overflowed does
  not under-report its operation count.
- The per-trace frame cap **MUST** preserve the opener. Pairing and retry-storm
  signals key on the first frame, and a long-lived subscription would otherwise
  drop it.
- A trace that lost frames or bytes **MUST** carry a truncation marker, and a
  producer that dropped frames **MUST** report the count. "Kept N of M" is never to
  be mistaken for "only N happened".

Cross-operation signals are a property of the engine, not of any one trace: a burst
of like operations (one host hammering `signing.createTransaction` several times in
under a second) is invisible to a single-trace view, so the engine groups by
`(channelId, opener frameId)` and marks the traces in a burst.

## 6. Transport and confinement

**The host dials outward.** The debugger is the server; the host is always the
client. This is forced, not stylistic: the on-device bridge binds loopback, and
nothing outside a browser can dial into a Web Worker. A passive `observe` hook plus
a relay would not reach either.

**Cleartext loopback, on every host type.** A debugger URL **MUST** be `ws://` on a
loopback host, and this **MUST** hold identically for the native sink and the web
host's worker link. Rationale, since the scheme looks like the weaker choice:

- TLS defends against a party on the path. A loopback socket has no path — the
  frames never reach an interface — so `wss://` adds no confidentiality here.
- `wss://` would require the debugger to present a certificate. One is not
  obtainable for `localhost` from a real CA, and a self-signed one costs an iOS
  developer a CA install *plus* a manual enable under Settings → General → About →
  Certificate Trust Settings before a single frame arrives.
- The concern cleartext raises — traces crossing an office network in the clear —
  is answered by the loopback requirement itself, and answered more strongly: the
  traces do not cross the network at all.

A remote debugger is therefore not a scheme change. It requires TLS **and**
authentication **and** an explicit opt-in; see §8(C).

**Validated string, dialled string.** A producer **MUST NOT** validate one string
and dial another. The native sink resolves the host and requires *every* resolved
address to be loopback, then dials the resolved address directly. The web worker
link has no resolver available and instead matches the hostname the URL parser
normalized — sound because the same string is handed to `new WebSocket`, so the
browser resolves exactly what was validated.

**A rejected URL MUST be visibly rejected.** Silently returning an inert link makes
a mistyped value read as "the debugger is broken" rather than "the debugger is
misconfigured".

**Server-side gates.** A debugger server **MUST**:

- bind loopback, so off-box peers cannot reach it;
- refuse the WebSocket upgrade unless `Origin` is a loopback host — a cross-origin
  browser page can otherwise dial a loopback server to inject frames or drive the
  decoder, which binding to loopback alone does not prevent. A non-browser client
  (CLI, curl) sends no `Origin` and is allowed;
- reject requests whose `Host` header is not an exact loopback name. A page from
  `evil.com` rebound to `127.0.0.1` issues same-origin requests that still carry
  `Host: evil.com`. The match **MUST** be exact, never a substring test that would
  read `127.0.0.1.evil.com` as loopback;
- cap accepted payload size.

**Embed tee.** An in-host embed that tees frames across a realm boundary **MUST**
pin the target to a verified host-owned frame, in both directions: it neither
forwards frames to nor accepts a mount from an untrusted window.

## 7. Decode posture

The debugger decodes every frame by default. There is no sensitive denylist, no
content heuristic, and no reveal toggle: a developer inspecting their own session
sees the real values.

A denylist would be a false guarantee — it is only as good as its marking, so a
secret-bearing method added without the annotation leaks — and it implies the tool
is safe to point at real traffic, which is the one use it must never have.

The guarantee is structural instead: **the tap and the decoder do not exist in a
production build.**

- The web host reads its debugger URL behind a build-time DEV condition that the
  bundler replaces with a literal, so a production bundle returns no URL
  unconditionally and a stray `localStorage` key cannot turn the tap on. With no
  URL the host never installs its emit callback, so the core never installs a sink.
- An in-host embed **MUST** be gated on a build-time flag, not a runtime toggle, so
  a production build has no panel to mount.
- The debugger package is private and dev-only, and is part of no product or host
  production bundle.

Decoding **MUST** reuse the generated codecs the client uses; a debugger **MUST
NOT** write its own. Decode is confined to the per-frame drill-down: the list view
is byte- and value-free in every configuration.

## 8. Surfaces

Every surface **MUST** drive the shared engine and the shared per-frame renderer,
so no surface can show a value — or a grouping, badge, or latency — the engine
would not. Chrome may differ: a surface may offer less navigation than another,
but **MUST NOT** offer a different answer.

**(A) Standalone inspector.** A loopback WS + HTTP server the host dials. Serves a
Network-tab-style web inspector and a CLI/REPL for headless or SSH work. The CLI
**MUST** be a client over the same HTTP endpoints as the web UI, rebuilding the
same view model, so the two cannot disagree about operations, badges, or payloads.

**(B) In-host embed.** A panel mounted inside the host, with no server and no
dial-out: the tap tees each envelope across the realm boundary to a host-owned
frame, which feeds the engine and decodes at the point of display. Frames never
leave the app, so each tab is its own tenant. This surface carries the shared
per-frame drill-down without the standalone's operation-list chrome — less
navigation, identical answers.

```
 TOP FRAME (host-owned)      engine + inspector, decodes at display
        ▲ raw bytes, payload-blind transport
 ───────┼──────────────────  realm boundary  ──────────────────────
 HOST REALM (iframe/worker)  core ── tap ──▶ tee to a verified top
```

**(C) Hosted relay.** Surfaces A and B only reach a host on the developer's own
machine. A deployed instance puts host and debugger on different machines. If
built, a hosted server **MUST** be a payload-blind relay: it authenticates a
per-instance token, routes opaque envelopes from the host holding that token to the
viewer holding the same token, and **MUST NOT** decode or store a value. Decode
runs in the developer's browser exactly as it does locally. Isolation is then a
routing property rather than a decode gate, which is what makes a shared relay
safe. The token **SHOULD** reuse the host's existing pairing flow rather than
invent one. This applies to native hosts, which can dial with a secret; a browser
host **MUST** use surface (B) instead, since dialling an external endpoint with a
token exposes it and fights the Origin rules.

## Non-goals

- No tap in `@parity/truapi` or the TS transport — the point of putting it in the
  core.
- No sensitive-frame redaction, denylist, or reveal path.
- No mocking or mutation. The tap is one-way. The `DebugSink` contract is also the
  extension point: a sink that reads a reply could deliver-modified or respond with
  no envelope or topology change.
