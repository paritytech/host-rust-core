# Re-establishing the product sandbox below JavaScript

_Design doc for the product container's egress and capability contract on Android and iOS. The Rust core migration deleted the JavaScript sandbox that enforced it; native interception replaced one part of it, and the rest is open._

## TL;DR

- **Goal:** restore the sandbox contract the JS container used to enforce, at a layer the product cannot reach — and state plainly what that contract now covers.
- **Recommendation:** Option 1 (per-platform native enforcement) for the P0. It needs no product-facing change and no new protocol surface, and it is the direction that made HTTP *stronger* than the container it replaced. Close WebSocket and WebRTC transport as named follow-ups rather than implying they are covered.
- The tradeoff to hold: **Android has always had two native gates and never had more.** The JS container sat on top of them blocking a further set of APIs, and deleting it removed that set without changing the native gates at all. The work is per-surface, not one switch.

## Goal

Android's product WebView has had native gates since `Feature/spa browser (#442)`, well
before the Rust core work: `shouldInterceptRequest` for HTTP requests and
`onPermissionRequest` for camera and microphone. Those are untouched by the migration.

On top of them, the JS container blocked a further set of APIs outright. The migration
deleted the container, so that set is now open. Nothing was traded — this is subtraction.

Android rows marked ✓ are measured on a device against the production
`WebViewPermissionClient`, not read off the source — see [Measured
behaviour](#measured-behaviour).

| Surface | Before migration | Today, Android | Today, iOS | |
|---|---|---|---|---|
| `fetch` | natively gated | natively gated ✓ | open | unchanged |
| `XMLHttpRequest` | JS threw, and natively gated | natively gated ✓ | open | loosened |
| `img` / `script` element loads | natively gated | natively gated ✓ | open | unchanged |
| `EventSource` | `undefined` | natively gated ✓ | open | loosened |
| `navigator.sendBeacon` | returned `false` | natively gated ✓ | open | loosened |
| WebRTC media (camera/mic) | JS gate + native gate | native gate | not implemented | ~unchanged |
| `WebSocket` | JS threw | **open** ✓ | open | regressed |
| WebRTC transport (ICE, `RTCDataChannel`) | JS gate | **open** ✓ | open | regressed |
| `indexedDB` | `undefined` | **open** ✓ | open | regressed |
| `document.cookie` | no-op getter/setter | **open** ✓ | open | regressed |
| iframe creation | blocked | **allowed** ✓ | allowed | regressed |
| `caches` | `undefined` | open on a secure origin | open | regressed |
| `SharedWorker` | `undefined` | unimplemented in WebView ✓ | open | moot on Android |

Three things to read off that table.

**`fetch` was never in the container's scope.** The primary modern HTTP API was carried by
the native gate the whole time, which is the strongest available evidence for where
enforcement belongs.

**The native gate is wider than expected.** It also covers `EventSource` and
`navigator.sendBeacon`, which the container had removed outright. Those two are therefore
*loosened* rather than regressed: a granted domain can now use them, but an ungranted one
still cannot. The regression is narrower and better-defined than a source reading suggests.

**iOS has no native gates at all**, so it lost the container's set with nothing underneath.
Every iOS cell in that table is "open" for the same single reason.

This doc answers:

1. Which parts of the old contract should be restored, which were deliberate, and which should stay dropped?
2. Which `RemotePermission` variants can the Rust core enforce, and which must each host enforce itself?
3. What mechanism should each host use, given that Android and iOS expose different interception primitives?
4. What does `WebRtc` actually gate — capture devices, network transport, or both?

Out of scope: `ChainSubmit`, `PreimageSubmit` and `StatementSubmit`, which the core
already enforces; device permissions other than camera and microphone; the dotli web
host, covered only where it constrains a shared decision.

## Measured behaviour

The Android rows above come from an instrumented conformance test that drives the production
`WebViewPermissionClient` and reports from the product's own point of view:

- `feature/products/impl/src/androidTest/.../isolation/SandboxEgressConformanceTest.kt`
- `feature/products/impl/src/androidTest/assets/sandbox-egress-probe.js`

The target is a loopback HTTP/WebSocket server running inside the test process, standing in
for a domain the product holds no grant for. Its own request log is the evidence: a request
recorded there left the WebView. A companion test grants the same domain and asserts every
surface *does* reach the server, so a blocked result can only be the gate and not an
unreachable fixture.

Run it with `./gradlew :feature:products:impl:connectedDebugAndroidTest`. Against an
ungranted domain, on API 34:

```
fetch                 blocked      server saw nothing
XMLHttpRequest        blocked      server saw nothing
img element           blocked      server saw nothing
script element        blocked      server saw nothing
EventSource           blocked      server saw nothing
navigator.sendBeacon  blocked      returned true, but server saw nothing
WebSocket             REACHABLE    server saw: WS /ws
indexedDB             present      no gate of any kind
document.cookie       present      cookie persisted
RTCPeerConnection     present      native binding — no JS gate installed
iframe creation       allowed      fresh realm exposes WebSocket: true

gate consulted 6 times, once per HTTP surface — never for the WebSocket
```

Three results are worth stating plainly.

**The WebSocket handshake is not an HTTP subresource**, so `shouldInterceptRequest` never
sees it. The gate was consulted six times — once for each HTTP surface — and not once for
the WebSocket, while the server recorded the completed handshake. That is direct evidence of
the bypass rather than an inference from reading the interceptor's contract.

**`navigator.sendBeacon` returns `true` and still goes nowhere.** The return value only
reports that the beacon was queued, so a JS-only probe would call this reachable. It is
gated. Any conformance check for this surface has to be corroborated server-side.

**A fresh iframe realm hands back an ungated `WebSocket`.** This is why the layer matters
more than the list: even a complete set of JS-level gates is escapable in one line, which is
the argument in [Why the JS lockdown was not sufficient](#why-the-js-lockdown-was-not-sufficient-even-when-it-was-live).

Two absences in the table are platform artifacts, not enforcement, and the host cannot rely
on either: `SharedWorker` is unimplemented in Android WebView, and `caches` requires a
secure context, which the test's cleartext origin is not — products served over `https` will
have it.

iOS is unmeasured. `WKWebView` has no equivalent harness, which is itself part of the
problem. For hosts without one, [`sandbox-probe.html`](sandbox-probe.html) in this directory
is the same probe as a standalone page: serve it, open it as a product, and read the table it
renders. It reports only what the product can see, so treat the Android test as the authority
wherever the two disagree — `sendBeacon` is exactly the surface a page-only probe gets wrong.

## Background / current state

### What the migration removed

Both hosts shipped the same lockdown in `product-container/src/index.ts`. It is still on
`master` for Android and on `develop` for iOS, byte-for-byte the same approach:

```js
// --- Network: intercept with error (future: permission-gated) ---
freezeValue(window, 'XMLHttpRequest', function () { throw new TypeError('Network access is not allowed') })
freezeValue(window, 'WebSocket',      function () { throw new TypeError('Network access is not allowed') })

// --- Network: delete (no future permission path) ---
freezeAndDelete(window, 'EventSource')
freezeValue(navigator, 'sendBeacon', () => false)

// --- Storage ---
freezeAndDelete(window, 'indexedDB')
freezeAndDelete(window, 'caches')
freezeAndDelete(window, 'SharedWorker')

freezeValue(window, 'RTCPeerConnection', webRtcManager.connectionClass)

// --- DOM: block iframe creation ---
if (tagName.toLowerCase() === 'iframe') throw new Error('iframe creation is not allowed')
```

`freezeValue` and `freezeAndDelete` are `Object.defineProperty` with
`writable: false, configurable: false`, so the product could not reassign them. The
iframe block existed because that is only true within one realm — a fresh iframe carries
pristine globals, so without it the freezes were trivially escapable.

**`fetch` is absent from that list, and always was.** The container blocked the legacy
HTTP API and WebSocket while leaving the primary modern one untouched. `fetch` was gated
by `shouldInterceptRequest` instead — a native hook that predates the Rust core work.
So the container was never the single chokepoint for HTTP; the native layer was, and
still is.

Deleting the container therefore changed nothing about HTTP and removed everything else:

- **`fetch` is unchanged.** Natively gated before, natively gated now.
- **`XMLHttpRequest` loosened**, from a hard `TypeError` to a permission gate. Arguably
  the one change in the right direction, since a blanket block is not a permission model.
- **WebRTC media is roughly unchanged** on Android — `onPermissionRequest` also predates
  the migration, and the JS gate sat above it.
- **`EventSource` and `sendBeacon` also loosened, not regressed.** Both turn out to be
  covered by the native gate, so removing the container moved them from unconditionally
  removed to permission-gated. Measured, not inferred.
- **`WebSocket` and WebRTC transport regressed** from blocked to open.
- **`indexedDB`, `caches`, `document.cookie` and iframe creation regressed** from removed to
  available. None is modelled as a `RemotePermission` variant, so they are absent from the
  protocol as well as the hosts.
- **iOS lost the container with nothing underneath.** It has neither native hook, so it
  is the only host where HTTP egress is ungated too.

The conformance test went with it. `IsolationProbeTest.kt` asserted eighteen sandbox
properties on a device and was deleted in the same commit as the container
(`bcf6c2e6e`), because it drove the JS engine the container ran inside. Its 325-line
fixture stayed in the tree, referencing a `container.js` asset that no longer exists — so
nothing had asserted any of those properties since. That is what
[Measured behaviour](#measured-behaviour) replaces, this time against the production
WebView client rather than a JS engine that no longer exists.

Two consequences for this design. Restoring parity with the container is not the goal:
several of those blocks were blunt, `indexedDB`/`caches` removal took away storage
products can reasonably expect, and a blanket `TypeError` was explicitly a placeholder —
the container's own comment reads *"future: permission-gated"*. And the surfaces it
covered but the protocol never modelled need a decision rather than an implementation:
either they belong in `RemotePermission`, or the sandbox drops them deliberately and says
so.

### The split that matters

```
 PRODUCT (WebView)
   │
   ├── truapi calls ──▶ ws://127.0.0.1 ──▶ RUST CORE ──▶ network
   │                                          │
   │                                    enforcement point
   │                                    exists and works:
   │                                    ChainSubmit
   │                                    PreimageSubmit
   │                                    StatementSubmit
   │
   └── fetch / WebSocket / WebRTC ─────────────────────▶ OS network stack
                                    (never sees the core)
                                          │
                                    enforcement point
                                    must be the WebView:
                                    Remote { domains }
                                    WebRtc
```

The core gates the first path at the two `PermissionsService::check_or_prompt_remote`
call sites in `rust/crates/truapi-server/src/runtime.rs`. Those bytes physically pass
through Rust, so the check is unavoidable.

The second path does not. A product's own `fetch` goes from the web engine straight to
the OS. RFC 0002 assumes otherwise — line 255 states *"the transport layer routes all
network calls through the Host"* — and that assumption is why the enforcement point was
never pinned down. The same line concedes the gap:

> How the Host enforces HTTP domain matching at the transport level (interception vs.
> validation before handing off) is an implementation detail left unspecified — should
> this RFC say more?

Three hosts filled that blank three different ways.

### What each host has today

**Android enforces HTTP and media, natively.** `WebViewPermissionClient.shouldInterceptRequest`
returns a 403 for any non-granted domain, and `ProductWebChromeClient.onPermissionRequest`
maps `RESOURCE_VIDEO_CAPTURE` / `RESOURCE_AUDIO_CAPTURE` onto the Camera and Microphone
grants. Both are wired to the product WebView through
`RealSpaHost` → `BrowserWebViewProvider`. This is the only real boundary either native
host has.

**iOS enforces neither.** No `WKContentRuleList`, no
`requestMediaCapturePermissionFor`. Its only gate, `webrtc-manager.ts`, is dead code:
it is the sole remaining file in `Packages/Products/product-container/` and
`WebRtcManager` is referenced nowhere on the branch.

**dotli is safe on WebRTC by omission.** It never sets `allow="camera; microphone"` on
the product iframe, and cross-origin frames are denied those features by default. It
has no CSP, so its HTTP egress is ungated like iOS's.

### Defects in the enforcement that does exist

These are conformance and behaviour bugs in Android's implementation, independent of
which option is chosen:

- **The wildcard matcher is more permissive than RFC 0002.**
  `generateDomainCandidates("deep.api.coingecko.com")` yields `*.coingecko.com`, so
  that grant covers arbitrary depth. RFC 0002 specifies single-level matching and names
  this exact counter-example: *"NOT `deep.api.coingecko.com`"*. Code and spec disagree.
- **An undocumented bypass list.** `fonts.googleapis.com`, `fonts.gstatic.com` and
  `paseo-bulletin-next-ipfs.polkadot.io` are allowed for every product with no prompt
  and no grant record. Two mean every product load contacts Google; the third is a
  testnet gateway on a production path.
- **`consumePermission` is the wrong primitive for interception.** One-time grants are
  single-use (`oneTimeGrants.remove`), so *Allow once* is spent by the first subresource
  and the next request to the same domain prompts again. A page with N assets from one
  domain can queue N dialogs, serialised by the guard's mutex.
- **`runBlocking` twice per subresource** inside `shouldInterceptRequest`, on a WebView
  worker thread, where the inner path can present UI and await a human.
- **`isForMainFrame` skips the check**, so top-level navigation is not domain-gated.

### Why the JS lockdown was not sufficient even when it was live

The container closed the *realm* escape — blocking iframe creation meant a product could
not obtain pristine globals. It did not close the *prototype-chain* escape, and for
WebRTC that is enough. `webrtc-manager.ts` defines:

```ts
return class GatedRTCPeerConnection extends nativeConnectionClass { … }
```

`extends` keeps the parent reachable in the same realm, so
`Object.getPrototypeOf(window.RTCPeerConnection)` returns the ungated class regardless of
how thoroughly the property is frozen. Freezing controls the binding, not the prototype
chain.

This is separate from the `fetch` omission. That was a scope gap — `fetch` was covered
natively and never needed the container. The prototype chain is a soundness gap: the
container tried to gate WebRTC and could not, in the same realm, with no iframe required.

So the old container was strong against the escape its authors anticipated and weak
against one they did not. That is the argument for enforcing below JavaScript rather than
building a better lockdown: a native hook has no prototype chain for the product to walk,
and no realm for it to escape into.

## Options

### Option 1 — Per-platform native enforcement, extending what Android proved

Each host enforces in its own WebView layer, below JavaScript. Android already does
this for HTTP and media; iOS builds the equivalent.

```
 ANDROID                              iOS
 shouldInterceptRequest ─▶ 403        WKContentRuleList ─▶ blocked
 onPermissionRequest ─▶ grant/deny    requestMediaCapturePermissionFor ─▶ grant/deny
        │                                     │
        └────────── same grant store ─────────┘
                  (RemotePermission)
```

**Trade-offs:**
- **Pros:** no product-facing change; no new protocol surface; enforcement sits where
  the product cannot reach it; Android's half is already shipped and load-bearing, so
  half the work is bug-fixing rather than greenfield.
- **Cons:** two implementations to keep in step, and they will drift — that is how the
  current state arose. Does not cover WebSocket on either platform. iOS's request-filtering
  capability is unverified (see Open questions).

### Option 2 — Content Security Policy, delivered by the host

The host sets `connect-src` on the product document from the granted domain set. One
policy covers `fetch`, `XMLHttpRequest`, `WebSocket`, `EventSource` and `sendBeacon`,
enforced by the web engine rather than by host code.

```
 granted domains ──▶ Content-Security-Policy: connect-src <domains>
                            │
                     web engine enforces
                            │
              fetch  XHR  WebSocket  EventSource  beacon
```

**Trade-offs:**
- **Pros:** the only mechanism that covers WebSocket at all; identical semantics on
  Android, iOS and dotli; no per-request host code, so no `runBlocking` on a load path.
- **Cons:** CSP must arrive in the document response headers or the initial markup. A
  `<meta http-equiv>` element inserted by script is ignored, so `addDocumentStartJavaScript`
  cannot deliver it. **Cost:** the host must control the product document's response,
  which means becoming an HTTP client (Android could rewrite in `shouldInterceptRequest`)
  or serving products over a custom scheme on iOS — a change to the origin model, with
  knock-on effects for storage partitioning. CSP is also fixed at load, so a grant made
  mid-session needs a reload or a pre-declared superset.

### Option 3 — Route product egress through the Rust core

Products stop using `fetch` for external calls and go through a TrUAPI method, making
the core the enforcement point for all five variants uniformly.

**Trade-offs:**
- **Pros:** one enforcement point, in Rust, testable without a device; identical on
  every host; matches how `ChainSubmit` already works.
- **Cons:** breaking, product-facing, and it forfeits what the engine provides —
  streaming, caching, CORS, cookies, `Response` semantics. Products written against
  standard web APIs stop working. **Cost:** every product migrates, and the core grows
  an HTTP/WS client surface it does not currently have.

## Comparison

| Axis | Option 1 — native | Option 2 — CSP | Option 3 — core-brokered |
|---|---|---|---|
| Covers `fetch` / XHR | yes | yes | yes |
| Covers WebSocket | **no** (measured) | yes | yes |
| Covers WebRTC transport | no | partly (`connect-src` does not govern ICE) | yes |
| Product-facing change | none | none | **breaking** |
| New protocol surface | none | none | substantial |
| Implementations to maintain | 2 (+dotli) | 1 policy, 2 delivery paths | 1 |
| Android work | fix 5 defects | new document-rewriting path | new client |
| iOS work | new, capability unverified | custom scheme, origin change | new client |
| Enforced below JS | yes | yes | yes |

## Recommendation

**Ship Option 1 for the P0. Scope WebSocket out of it explicitly, and treat Option 2 as the follow-up that closes WebSocket once its delivery path is settled.**

Reasons:

1. **It is the only option that closes iOS's total absence without a product-facing or
   protocol change.** iOS today enforces nothing; a media-capture delegate plus request
   filtering is bounded, well-understood work.
2. **Half of it is already proven.** Android's interception is live on the product
   WebView. Five defects need fixing, but the mechanism and its wiring are not in
   question — which is a materially lower risk than starting either alternative.
3. **Option 2 is right and not yet actionable.** Its blocker is delivery, not policy:
   CSP cannot be injected by script, so someone must own the product document's
   response. That is a real design task with an origin-model consequence on iOS, and it
   should not gate closing the iOS hole.
4. **Option 3 is disproportionate.** It trades every browser networking affordance for
   uniformity, and breaks existing products. The uniformity is worth having, but not at
   that price, and not on a P0 timeline.
5. **It is the only layer that has survived a migration.** `fetch` is gated today because
   `shouldInterceptRequest` was never the container's job to do and so was never deleted
   with it. The JS layer around it was removed in one commit and took eight surfaces with
   it. Option 1 puts the remaining surfaces where the durable gate already is.

What Option 1 does **not** cover, stated so the contract is honest: WebSocket,
`EventSource`, `sendBeacon`, and WebRTC transport. Those were gated by the old container
and are open now. Option 1 leaves them open; Option 2 closes the first three, and WebRTC
transport is not addressed by any option here (see Open questions).

**Do not restore the old freezes as an interim measure.** They are bypassable without the
iframe block, and reinstating the iframe block breaks legitimate products. A JS lockdown
is only coherent as a whole, and it is the design the migration deliberately left.

## Interface / contract

No change to the protocol surface is required for Option 1. The existing types are the
contract:

```rust
/// One remote-operation permission requested by the product (RFC 0002).
pub enum RemotePermission {
    /// Outbound HTTP/WebSocket access to a set of domains.
    Remote { domains: Vec<String> },
    /// WebRTC media access.
    WebRtc,
    ChainSubmit,
    PreimageSubmit,
    StatementSubmit,
}
```

Enforcement responsibility, which is what this doc pins down:

| Variant | Enforced by | Status |
|---|---|---|
| `ChainSubmit` | core — `runtime.rs`, `check_or_prompt_remote` | done |
| `PreimageSubmit` | core | done |
| `StatementSubmit` | core | done |
| `Remote { domains }` | host WebView, per platform | Android HTTP surfaces only, iOS absent |
| `WebRtc` | host WebView, per platform | Android media only, transport open; iOS absent |

Note what the table does **not** contain. The old container gated `EventSource`,
`sendBeacon`, `indexedDB`, `caches`, `SharedWorker` and iframe creation, and none of
those has a `RemotePermission` variant. They were enforced by a layer that no longer
exists, against a contract that was never written into the protocol. Whatever the sandbox
guarantees about them now is undefined rather than decided.

Three protocol questions fall out and belong in a truapi RFC, not here:

- **`WebRtc` conflates capture and transport.** It is documented as "WebRTC media
  access" but named for the whole subsystem, and Android implements it as Camera +
  Microphone. An `RTCDataChannel` with no media triggers nothing on any host. If these
  are two decisions, they need two variants.
- **Wildcard depth.** RFC 0002 specifies single-level; Android implements arbitrary
  depth. One of them moves, and the spec is the place to settle which.
- **The unmodelled surfaces.** For each of `EventSource`, `sendBeacon`, `indexedDB`,
  `caches`, `SharedWorker` and iframe creation: modelled as a permission, allowed
  unconditionally, or denied unconditionally. `EventSource` and `sendBeacon` are HTTP
  underneath, so Android's existing interception may already cover them — that is worth
  checking before adding surface.

## Migration considerations

1. **Write down what the sandbox guarantees today.** No dependencies, and it gates the
   rest: the table in Goal is the current contract, and nobody has agreed it. Until the
   unmodelled surfaces have a verdict, "the sandbox" means different things to different
   people.
2. **Check whether Android's interception already covers `EventSource` and
   `sendBeacon`.** Both are HTTP underneath, so they may be gated already. Cheap to
   verify, and it shrinks the list before any design work.
3. **Fix Android's conformance defects.** Independent of everything else: wildcard depth,
   the bypass list, `consumePermission` → a non-consuming `check` in the interception
   path, `isForMainFrame`, and the `runBlocking` pair.
4. **Delete both orphaned `webrtc-manager.ts` files.** Dead gating code reads as
   coverage; it is worse than none.
5. **iOS: implement `requestMediaCapturePermissionFor`.** Depends on nothing. Closes
   WebRTC media, and is the smallest change with real security value on that platform.
6. **iOS: request filtering.** Depends on the Open question below resolving.
7. **Settle the protocol questions in an RFC under [`docs/rfcs/`](../../rfcs/_index.md)**
   (0025 is claimed by an open PR and 0026 is taken, so 0027 is the next free number).
   Depends on 1, 2 and 3 — the RFC should record decisions, not discover them.
8. **Option 2 spike: who owns the product document response?** Depends on 5 and 6
   landing, so the P0 is not blocked behind it.

> Note: iOS may already be fail-closed for media capture by accident. When
> `requestMediaCapturePermissionFor` is unimplemented, WebKit's default is not
> obviously "allow", so `getUserMedia` may simply fail today. That changes the
> *severity* of step 3 but not its necessity — accidental denial is not a grant model,
> and it will silently become permissive if the delegate is added for another reason.
> Confirm on a device before assigning priority.

## Open questions for the team

1. **What can `WKContentRuleList` actually filter?** The recommendation's iOS half
   depends on whether WebKit content-blocker rules cover XHR/fetch (`raw`) and
   WebSocket resource types. Published summaries disagree and this was not verified.
   Resolve with a device spike before committing to step 4 — if the answer is "not
   WebSocket", that is expected; if it is "not fetch either", Option 1 loses its iOS
   half and Option 2 becomes the P0.
2. **Is `Allow once` meaningful for network egress at all?** A single page load makes
   many requests to one domain. Per-request consumption is wrong, but so is treating
   one dialog as consent for a whole session. Per-domain-per-page-load may be the only
   coherent middle.
3. **Should the bypass list exist, and if so where?** Google Fonts on every product
   load is a privacy decision, not an implementation detail, and it currently lives in
   a Kotlin `setOf`.
4. **Does `WebRtc` split?** Answering this in the RFC determines whether transport
   gating is in scope for this work or a later one.
5. **Which of the unmodelled surfaces do we actually want closed?** The old container
   removed `indexedDB`, `caches` and `SharedWorker`, which is stricter than products can
   reasonably be expected to tolerate — offline storage is a normal expectation. Deciding
   these is a product question as much as a security one, and it should be decided rather
   than inherited from whatever the container happened to do.
6. **Was iframe creation blocked for isolation, or only to protect the freezes?** If the
   latter, it has no purpose once enforcement moves below JavaScript, and products get
   iframes back for free. If the former, nothing currently replaces it.

## Status & tracking

PR stack, what is built versus planned, and open tasks: tracking issue TBD.

## References

- [RFC 0002 — Permission Model for Host API](../../rfcs/0002-permission-model.md) — line 51 assigns enforcement to the host sandbox; line 255 leaves the mechanism unspecified; line 133 specifies single-level wildcards
- `rust/crates/truapi-server/src/runtime.rs` — the core's existing enforcement point, at the `check_or_prompt_remote` call sites
- `rust/crates/truapi/src/v01/permissions.rs` — `RemotePermission`, `HostDevicePermissionRequest`
- The deleted lockdown, for reference: `product-container/src/index.ts` on
  `polkadot-app-android-v2@master` and `polkadot-app-ios-v2@develop`
- `polkadot-app-android-v2` — `WebViewPermissionClient.kt`, `ProductWebChromeClient.kt`, `NetworkAccessPermissionHandler.kt`, `ProductPermissionGuard.kt`
- `polkadot-app-ios-v2` (`codex/truapi-rust-core`) — `SPAJSEngine.swift`, orphaned `product-container/src/webrtc-manager.ts`
- `dotli-community` — `packages/ui/src/bridge.ts:764` (iframe sandbox), `host-callbacks/PromptPermission.ts`
