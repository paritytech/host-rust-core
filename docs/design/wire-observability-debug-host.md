# Wire Observability and Debug Host

|                    |                                  |
| ------------------ | -------------------------------- |
| **Start Date**     | 2026-07-25                       |
| **Authors**        | Nidish Ramakrishnan              |
| **Implementation** | #295 (Rust tap), #536 (debugger) |
| **Tracking**       | sdk-team#26                      |

## Scope

Contracts for a TrUAPI wire debugger and the host tap that feeds it: tap
placement, the sink contract, the envelope and its wire-contract identity,
correlation, retention, confinement, decode posture, the surfaces, and
enablement reporting.

Out of scope: tuning values, UI layout, file structure. **MUST** / **MUST NOT** /
**SHOULD** carry their usual force.

## Model

Product↔host TrUAPI traffic is opaque SCALE frames. A tap in the Rust host core
emits every frame as opaque bytes; the debugger correlates and decodes them. The
core never decodes. The host always dials the debugger. The tap compiles into
every build and is inert until a sink is installed; the decoder is absent from a
production product bundle.

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
It **MUST NOT** exist in `@parity/truapi` or the TypeScript transport, and **MUST
NOT** be reachable from the product side. The product package carries no debug
seam.

`truapi-server` has two frame choke points; every host — web, iOS, Android, CLI —
funnels through them:

| Direction                 | Choke point                                            | Ordering                      |
| ------------------------- | ------------------------------------------------------ | ----------------------------- |
| inbound (product → core)  | `ProductRuntime::receive_frame()`                      | taps **before** decode        |
| outbound (core → product) | `FrameSink::emit_frame()`, via `SinkTransport::send()` | delivers **first**, then taps |

Inbound taps before decode so a corrupt frame is still observed. Outbound
delivers first so no frame waits on the tap.

## 2. Sink contract

A sink is installed per product channel (`ProductRuntime::set_debug_sink`) and is
unset by default.

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

- `emit` **MUST NOT** block the frame path and **MUST NOT** fail the operation
  that produced the event. A slow, absent, or crashed debugger loses a trace; it
  **MUST NOT** lose a session.
- `emit` **MUST NOT** panic. A sink may be out-of-repo, and a panic there unwinds
  into a live dispatch. Both in-path call sites **SHOULD** contain one
  (`catch_unwind`), which holds only where unwinding is enabled: the workspace
  release profile sets `panic = "abort"`, so in the release and xcframework
  artifacts that carry the `ws-bridge` sink a panicking sink aborts the process
  and no call-site guard can contain it. Containment is a dev-and-test
  protection; the contract on the sink is what holds in a shipped host.
- The core **MUST** pass frame bytes through untouched, and **MUST NOT** decode,
  inspect, or redact them.
- A sink that owns a socket **MUST** bound its backlog by both count and bytes,
  and **MUST** report the frames it dropped.

## 3. Envelope and wire identity

Each tapped frame becomes one envelope. The identity fields are flat siblings of
the payload fields, not a nested block:

```
{ v, codec, schema, channelId, dir, observedAt?, frame, dropped? }
```

`frame` is the untouched SCALE `ProtocolMessage`, base64 over a text transport.
`dir` is product-vantage: `out` = left the product, `in` = arrived at it. The Rust
tap names directions host-vantage internally and flips them on the way out.

`dropped` counts frames the producer shed since the previous envelope and **MUST**
be omitted when zero, so the common envelope carries no extra field. It is how §2's
"report the frames it dropped" reaches the debugger, which sums it per channel.

`observedAt` is the producer's own clock at the moment the frame crossed. A
producer that buffers **SHOULD** stamp it: the debugger's receive time is the flush
instant for anything that waited in a queue, which collapses a backlog's durations
to zero and pulls operations minutes apart into one retry-storm window. A producer
that omits it accepts those artefacts. (The web link stamps it; the native sink
does not yet, and buffers 4096 frames across reconnects, so native traces are
subject to exactly that skew.)

A producer **MUST** stamp a wire-contract identity: `v`, the envelope version;
`codec`, the coarse codec version; and `schema`, a hash over every frame id, its
method leg, its direction, and its payload shape. Frame ids are `u8` discriminants that get reassigned
as the API evolves, so a frame from a host on a different contract decodes to the
wrong method with a plausible-looking result.

- A debugger **MUST** enable decode only for a channel whose schema hash
  affirmatively matches its own, **and** only for a frame whose producer
  affirmatively attested. Both gates apply. Channel-only keying latches: one
  attested frame marks the channel trusted and every later frame inherits it.
  Frame-only keying loses the standing verdict that a channel declared a foreign
  contract.
- An absent or mismatched identity **MUST** still group (grouping is
  payload-blind) and **MUST NOT** be trusted to decode. The match is affirmative,
  not a rejection of known-bad values.
- Every producer stamps it, including a tee that never leaves the page. A tap on
  the far side of a worker or realm boundary cannot read the core's hash, so the
  core **MUST** expose it outward and the tee **MUST** carry it.

## 4. Correlation

- Traces **MUST** be keyed on `(channelId, requestId)`, not `requestId` alone:
  each host mints its own `p:1`, `p:2`, …, so two hosts collide. This `requestId`
  is the one product-sdk telemetry spans correlate on.
- A frame's lifecycle role (request / response / start / receive / …) **MUST** be
  resolved at ingest as a pure function of its frame id against the wire table. It
  is not correlation state and **MUST NOT** be reconstructed from observed
  ordering. A vantage with no frame id, and an off-table id, resolve to `unknown`.
- A product may recycle a `requestId`. When a fresh opener arrives for an id whose
  current operation already opened, the engine **MUST** rotate to a new generation
  rather than merge two calls.
- An undecodable frame **MUST** be surfaced as a `malformed` sentinel, not
  dropped.
- "Opener with no close" and "close with no opener" **MUST NOT** share one badge.
  The first is a claim about the host. The second is usually a property of the
  debugger: the tap attached mid-operation, retention dropped the opener, or the
  frame id is off this debugger's table. A debugger **MUST NOT** guess which
  produced an opener-less close; positional pairing carries no provenance.
- Retained id strings **MUST** be length-clamped. Real ids are short
  (`myapp.dot`, `p:1`).

## 5. Retention

Retention **MUST** be bounded on three axes — retained traces, frames per trace,
bytes per trace — and every bound **MUST** surface rather than misreport:

- Whole-operation evictions **MUST** be counted.
- The per-trace frame cap **MUST** preserve the opener, and **MUST** locate it by
  role rather than by position. `frames[0]` is not the opener in the general case:
  every tap attaches mid-session, so the first frame observed for an id is often a
  closer, which puts the real opener at index >= 1.
- A trace that lost frames or bytes **MUST** carry a truncation marker, and a
  producer that dropped frames **MUST** report the count.

Cross-operation signals belong to the engine, not to any one trace: the engine
groups by `(channelId, opener frameId)` and marks the traces in a burst.

## 6. Transport and confinement

The debugger is the server; the host always dials outward. The on-device bridge
binds loopback, and nothing outside a browser can dial into a Web Worker.

A debugger URL **MUST** be `ws://` on a loopback host, identically for the native
sink and the web host's worker link. A loopback socket has no path for TLS to
defend, and a `localhost` certificate costs an iOS developer a CA install and a
manual trust toggle.

The envelope carries the frame as base64 of the untouched SCALE payload (§3), so
decode-off is a rendering switch in the debugger, not a confidentiality measure:
anyone on the path decodes those frames with the published `@parity/truapi`
codecs and the exported schema hash. Loopback confinement, not encryption, is
what keeps frames off a network.

A producer **MUST NOT** validate one string and dial another. The native sink
requires every resolved address to be loopback and dials the resolved address;
the web worker link, with no resolver, matches the hostname the URL parser
normalized and hands that same string to `new WebSocket`. A rejected URL **MUST**
be visibly rejected.

A debugger server **MUST**:

- bind loopback by default. A non-loopback bind is hosted mode and **MUST**
  satisfy §8(C) before it binds;
- keep the three loopback classifications distinct — origin (who may dial in),
  target (what `Host` the server answers for), bind (which interface to listen
  on). `sub.localhost` is a legitimate dial-in origin and is never a loopback
  interface, so one shared predicate lets a hosted bind pass as loopback and skip
  the token requirement;
- refuse the WebSocket upgrade unless `Origin` is a loopback host. A cross-origin
  browser page can otherwise dial a loopback server to inject frames or drive the
  decoder. A non-browser client (CLI, curl) sends no `Origin` and is allowed;
- reject requests whose `Host` header is not an exact loopback name. A page from
  `evil.com` rebound to `127.0.0.1` issues same-origin requests still carrying
  `Host: evil.com`. The match **MUST** be exact, never a substring test that would
  read `127.0.0.1.evil.com` as loopback;
- cap accepted payload size.

An in-host embed that tees frames **across a realm boundary MUST** pin the target
to a verified host-owned frame in both directions: it neither forwards frames to
nor accepts a mount from an untrusted window. This binds any cross-realm embed;
the embed that exists today is same-realm (§8(B)) and crosses no boundary, so it
has no target to pin.

## 7. Decode posture

The debugger decodes every frame. There is no sensitive denylist, no content
heuristic, and no reveal toggle. A denylist is only as good as its marking, so one
secret-bearing method added without the annotation leaks.

The guarantee is structural, and its two halves are not equally strong.

The **decoder** is absent from a production bundle: the debugger is a development
dependency behind a build-time flag, so a production build drops the module
outright. That is the checkable half.

The **tap** is not absent. `DebugSink`, both call sites, and `set_debug_sink`
compile into every build of the core, including release and wasm32, and the
native sink ships under the `ws-bridge` feature that the release and xcframework
artifacts enable. What holds in production is that the tap is **inert**: no host
installs a sink, so the frame path costs an unset-sink check. An
implementation **MUST NOT** describe the tap as absent from a shipped host, and
**MUST NOT** rely on its absence for any safety property - only on no sink being
installed, which §9's enablement rules govern.

- The web host reads its debugger URL behind a build-time DEV condition, so a
  production bundle returns no URL and a stray `localStorage` key cannot turn the
  tap on. With no URL the host installs no emit callback, so the core installs no
  sink. The condition **MUST** be the bare token the bundler substitutes
  (`import.meta.env.DEV`) — no alias, no optional chaining. A bundler replaces
  that exact token and nothing else; an aliased read survives into the bundle,
  reads `undefined`, and disables the tap in every build.
- The switch's **presence** and the URL it holds are two separate reads, and only
  the second is DEV-gated. A production build **MUST** still be able to observe
  that the switch is set, because that is what §9's one production message keys
  on; it **MUST NOT** read a URL from it, dial, or install a sink. Collapsing the
  two into one DEV-gated read makes that message unreachable in the only build
  that needs it.
- An in-host embed **MUST** be gated on a build-time flag, not a runtime toggle.
- An embedding host **MUST** take the debugger package as a development
  dependency behind that flag, so a production build drops the module and its
  decoder. The property to assert in CI is absence from the production bundle.

Decoding **MUST** reuse the generated codecs the client uses; a debugger **MUST
NOT** write its own. Decode is confined to the per-frame drill-down; the list view
is byte- and value-free in every configuration.

## 8. Surfaces

Every surface **MUST** drive the shared engine and the shared per-frame renderer,
so no surface shows a value, grouping, badge, or latency the engine would not.
Chrome may differ between surfaces; the answer **MUST NOT**.

**(A) Standalone inspector.** A loopback WS + HTTP server the host dials, serving
a Network-tab-style inspector over HTTP endpoints that expose the same view model
the page renders. Any other client — a script, `curl`, a headless check — **MUST**
use those endpoints rather than a parallel read path.

**(B) In-host embed.** A panel mounted inside the host, with no server and no
dial-out. The host hands each tapped envelope to the panel in its own realm, which
feeds the engine and decodes at the point of display. Frames never leave the app,
so each tab is its own tenant. Chrome may be reduced where a host has no room for
it.

```
 HOST REALM (one page)   core ── tap ──▶ engine + inspector, decodes at display
                                        no server, no socket, no realm crossing
```

**Cross-realm tee — specified, not built.** A host whose core runs in a worker or
iframe cannot hand frames over directly, and would tee them to a host-owned top
frame instead:

```
 TOP FRAME (host-owned)      engine + inspector, decodes at display
        ▲ raw bytes, payload-blind transport
 ───────┼──────────────────  realm boundary  ──────────────────────
 HOST REALM (iframe/worker)  core ── tap ──▶ tee to a verified top
```

That shape is what §6's embed-tee rule governs. No producer implements it: the
embed takes frames through a direct call in the same realm, so nothing in the tree
sends or receives a cross-realm debug message. Until one does, an implementation
**MUST NOT** claim the embed is isolated from an untrusted window - there is no
window boundary in play to isolate it from.

**(C) Hosted mode — specified, not built.** A and B reach only a host on the
developer's own machine; a non-loopback bind removes that restriction. Four
requirements apply:

- It **MUST** be token-scoped. The token is at least 16 url-safe characters and
  gates every request — the WS upgrade and every HTTP route, including the UI
  page. Gating data but serving chrome unauthenticated renders an empty inspector.
- It **MUST** refuse to bind without one, and **MUST** refuse before binding.
- It **MUST NOT** decode values, whatever the caller asked for. There is no
  denylist (§7), so every frame decodes, including ones carrying key material. The
  switch is forced off, not defaulted off. This bounds what the debugger displays,
  not what crosses the wire (§6).
- It is for native hosts only. A browser host **MUST** use (B); dialling an
  external endpoint with a token exposes the token to the page.

The `Host` rule in §6 applies with the bound address added to the exact-match set.

It is unbuilt because it has no possible client: a browser host is excluded by the
fourth requirement, and a native host neither leaves loopback (§6) nor carries a
token on its upgrade. Reaching it requires three things this document does not
specify — a non-loopback escape hatch in the sink's address check, token carriage
on the sink's upgrade, and a `Host` rule accepting a request's own authority when
the bind is unspecified. Until those exist, an implementation **MUST NOT** present
hosted mode as a reachable capability.

A hosted debugger would stream plaintext product traffic across the network
between host and viewer (§6). That exposure is unmitigated.

## 9. Enablement

A dev build is told to dial by a host-specific switch: a browser host reads a
per-origin store, a native host takes an injected value. Neither is a URL
parameter.

The browser store is read in the realm that creates the host runtime — the shell
page in one embedding, an iframe realm in another — and is per-origin, so a value
set on any other origin is invisible.

Reading whether the switch is set is distinct from reading what it holds (§7).
The production message below depends on the first surviving into a production
build; the dial depends on the second, which does not.

A host with a dial path **MUST** report it: one that does not dial says so once,
one that does says where, each naming the source it read. Today only the web host
has such a path - the native sink has no host wiring it up - so this binds the web
host now and every host as its dial path lands. The debugger's own viewer
holds a socket, so its socket count moves whether or not a host connected, and an
empty board with a live socket is indistinguishable from a host nobody switched
on. The message **MUST NOT** appear in a production build, with one exception: a
host whose switch is **set** while the build is production **MUST** say so once.

Silence is only safe when nobody asked, and the switch being set is the record
that someone asked. The dial is behind a build-time DEV condition, and a host may
have no dev-mode build in its local workflow at all: dot.li ships `build` and
`preview` scripts and no dev server, so its normal local build compiles the dial
out. Setting the documented per-origin value on such a build then produces no dial
and no message, which reads as a broken debugger rather than a build that cannot
carry one.

The switch is what separates the two cases, so it is what the rule keys on. A
production build nobody is debugging has no switch set and stays silent; a
production build someone is trying to debug has one, and gets told why nothing
dialled. The message must not assert _why_ the condition failed: a host cannot
distinguish a production build from a bundler that never substituted the token,
since both leave the condition false.

## Non-goals

- No tap in `@parity/truapi` or the TS transport.
- No sensitive-frame redaction, denylist, or reveal path.
- No mocking or mutation. The tap is one-way. `DebugSink` is where mutation would
  go if wanted: a sink that reads a reply could deliver a modified one, with no
  envelope or topology change.
