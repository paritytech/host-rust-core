# truapi-host-cli

Headless TrUAPI hosts for local end-to-end testing, built on `truapi-server`.
They replace the external signing-bot service: two CLI processes take the two
host-spec §B roles and pair over the **real People-chain statement store** (the
same node an iOS/web client uses), so tests run against a real signer with no
Novasama-operated dependency.

See [SPEC.md](SPEC.md) for the complete as-built v0.1 behavior and engineering
contract.

Either host can be driven by a **product script** you write: a JS/TS file that
receives a global `truapi` (the `@parity/truapi` client, scoped to a product id)
and calls it like any product would. With `--script`, the CLI runs the script
and exits with its status. Without `--script`, both roles open a full-screen
terminal UI when stdin and stdout are TTYs.

One binary, `truapi-host`:

| Command | Role |
| --- | --- |
| `pairing-host` | Seedless host: serves product frames, emits pairing deeplinks, and can run product scripts. |
| `signing-host` | Wallet-local host: owns signer identity, can run product scripts, accepts pairing deeplinks, registers statement allowance on-chain, signs. |
| `identity-check` | Probe the root and canonical `uid.dot` identity account for a registered username (read from the dotNS contracts on Asset Hub). |
| `register-name` | Register a full-person username via `DotnsGateway.register_name` on Asset Hub, linked to a lite username or standalone with a chat key. |
| `alloc-check` | Diagnose (or `--submit`) on-chain statement-store allowance: ring membership, chosen slot, and the `set_statement_store_account` extrinsic. On a full period it prints each occupied slot's age and which one would be replaced. |
| `pgas-check` | Diagnose (or `--submit`) an Asset Hub PGAS allowance claim: ring membership on People, whether Asset Hub has imported that ring revision, the day's first unclaimed slot, and the `Pgas.claim_pgas` extrinsic. |

The repository's `make e2e-dotli` target builds this binary and runs the
dotli/playground Diagnosis suite with a non-interactive signing-host responder.
It verifies the initial pairing, remote signing, host sign-out, and
same-account reconnect without the external signer-bot service.

## Quick start

```bash
make headless install  # build dependencies and install truapi-host once
truapi-host signing-host
```

Product frames use a private, per-process WebSocket-over-Unix-domain-socket by
default, so starting either host does not reserve a TCP port. Pass
`--frame-listen 127.0.0.1:0` to expose an ordinary loopback WebSocket instead;
this is required for browser clients, which cannot open filesystem sockets.

### Browser products

A browser product reaches that socket through `@parity/truapi`'s sandbox. Start
the host on a fixed port, and point the product at it before anything else
touches the client:

```bash
truapi-host signing-host --frame-listen 127.0.0.1:9955 --product-id my-product.dot
```

```ts
import { connectWebSocketHost } from "@parity/truapi/sandbox";

connectWebSocketHost("ws://127.0.0.1:9955");
```

The product is then detected as hosted and holds the real product account for
its own `.dot` name, so signing, statements, entropy, permissions and storage
all take their production code paths with no phone involved. `--product-id` is
not optional: the host derives the product account from it and refuses to *sign*
for any other product id, and a mismatch only surfaces later, as a
`PermissionDenied` on the first signature.

Two players on one machine means two hosts, each with its own session and port
(`--session bob --frame-listen 127.0.0.1:9956`), and a second product instance
pointed at the second port. Sessions isolate the signer, the storage and the
permissions.

The signing host opens an interactive terminal where you can paste a pairing
link, type `/pair <link>`, run `/script`, or use `/help` to discover the
available commands. It uses `--mnemonic` / `HOST_CLI_SIGNER_MNEMONIC` if set.
Otherwise it auto-selects or creates a stored account under `--base-path` (default
`$XDG_STATE_HOME/truapi-host` or `~/.local/state/truapi-host`), attests it
through the identity backend, waits for ring readiness, and rotates when the
current account exhausts Statement Store slots. A full period replaces the
oldest slot past the runtime's replacement cooldown, so rotation only happens
when no slot is replaceable.

### Interactive terminal UI

In a TTY, both hosts open the same scrollable transcript above a single command
bar. Host lifecycle events, tracing logs, every incoming SSO request, script
stdout/stderr, commands, and approval prompts all use that transcript, so
background output cannot overwrite input. On `signing-host`, `--deeplink URL`
opens the UI and starts the pairing response after initialization.

Commands always start with `/`:

| Command | Result |
| --- | --- |
| `/pair <url>` | Validate and answer a `polkadotapp://pair?...` deeplink (signing host). |
| `/script` | Reopen the session's last TypeScript scratch script (or create one), then run it. |
| `/script <path>` | Remember and run an existing JS/TS product script through the public frame endpoint. |
| `/login` | Start pairing for the selected product and copy its deeplink to the clipboard. |
| `/logout` | Disconnect the pairing host and discard its old pairing keypair. |
| `/log <level>` | Change tracing to `error`, `warn`, `info`, `debug`, or `trace`. |
| `/product` | Show the currently selected product. |
| `/product <id>` | Switch the product used by future scripts and frame connections. |
| `/session` | Show the current session name, path, and user id (signing host). |
| `/session <name>` | Switch to or create an isolated signing-host session. |
| `/session --list` | List user sessions for the current network. |
| `/help` | Show commands and keyboard shortcuts. |
| `/clear` | Clear the visible transcript. |
| `/copy` | Copy the retained transcript to the system clipboard. |
| `/quit` | Shut down cleanly. |

Typing `/` opens autocomplete. Up/Down selects a completion; with the menu
closed it navigates process-local command history. Tab inserts a completion,
and `/script` completes filesystem paths. Ctrl-U/Ctrl-D scroll by half a
viewport, End restores auto-follow, Esc closes autocomplete, and Ctrl-C clears
input, cancels a running command, or exits when idle. Deeplinks are deliberately
not persisted in history across processes.

On `pairing-host`, `/logout` cancels an in-flight pairing, disconnects the
current signing host, and removes the old pairing identity. The next product
login request or operator `/login` generates a new keypair and emits a fresh
link that can be answered by another signing host. `/login` uses the current
`/product` selection, copies the generated deeplink to the system clipboard,
and remains interactive while the TUI renders pairing progress. A clipboard
failure is reported without cancelling pairing. Logout does not clear product
storage, scripts, or the selected product.

Both `pairing-host` and `signing-host` use the same interactive UI and command
bar. It uses a quiet, command-centered transcript: submitted
commands title full-width dividers, script stdout keeps the terminal's normal
foreground, stderr has a small error gutter, and lifecycle work updates
sentence-case status rows in place. A compact
`TrUAPI <role> host · 👤 <name> · 🌐 <network> · 📦 <product>` status sits
below the writing bar. Long product names are ellipsized, while session and log
level stay out of that bar. A borderless, subtly backgrounded composer anchors
autocomplete and the `›` prompt while keeping the native cursor after the
input. When the input is empty, command guidance appears there as a placeholder
instead of occupying status space. Set `NO_COLOR=1` to remove semantic colors
and the surface fill without losing spacing, status symbols, or wording.

Non-interactive `--script` and `exec` runs use the same sentence-case event
copy and status symbols without the full-screen chrome. This keeps captured
logs readable while pairing URLs remain directly extractable by automation.
`/copy` copies readable transcript text without UI chrome or complete pairing
links. Captured script output is plain text: the host strips terminal control
sequences before adding child output to the transcript. Raw ANSI styling such
as bold is therefore not rendered in the full-screen UI.

Bare `/script` reopens the last script recorded for the active session,
including a path previously selected with `/script <path>`. If that file is
missing or the session has no script yet, it creates a durable Bun TypeScript
file under the active host state's `scripts/` directory. The dependency-free
starter uses ANSI colors and calls `truapi.account.getUserId()`. Scripts opened
from an npm project can import packages installed by that project.
The TUI temporarily yields the terminal to `$VISUAL`, then `$EDITOR`, or
`vi` when neither is set. After the editor exits successfully, the TUI is
restored and the saved script runs through the public frame endpoint. Editor
settings containing arguments, such as `EDITOR='code --wait'`, are supported.

Managed sessions isolate signer accounts, product/core storage, and permissions.
Once a signer identity is known, its public session name is the Lite username
and its files live under
`<base-path>/<network>/<username>_signing_host`. Provisional and legacy named
sessions are promoted to that user-owned root, so an old name such as `pgtest`
does not remain the durable namespace. The selected username is remembered per
network but is not repeated in the status bar as a separate session field.
`default` remains only as a compatibility/bootstrap location until a username
is resolved. It is hidden from session completion and listing and cannot be
selected with `/session default`. User session names contain lowercase ASCII
letters, digits, `.`, `_`, or `-`; they cannot be paths. Switching prepares the
target while the old session remains active, then stops its pairing responder
and resets product WebSocket connections so clients reconnect against the new
runtime.
New auto-managed accounts use the session name as their Lite username prefix;
characters other than lowercase letters are omitted. For example, session
`pgtest` creates usernames beginning with `pgtest`. An explicit
`--lite-username-prefix` takes precedence, and `default` retains the historical
`headless` prefix. `--reserved-username <label>` additionally reserves a
full-person base name on dotNS for a newly created account, to be claimed later
with `register-name`; the CLI refuses labels the registrar has already minted.
The selected username and last script reference are cached in `session.json`
inside the displayed session path. Scratch scripts use a portable filename;
explicit scripts use an absolute path. On restart, an
already-provisioned local signer is activated from disk without an
identity-backend or ring-membership round trip, and bare `/script` restores that
session's editor context. A session with no signer yet reports
`<not provisioned>` and the transcript prompts the user to run
`/session <name>`. Inspecting with bare `/session` never starts network
onboarding; naming a different session creates and connects its user.

Select or create a session at startup with:

```bash
truapi-host signing-host --session alice
```

`--session` cannot be combined with `--account` or `--mnemonic`. A host
started with an explicit mnemonic reports an `ephemeral` session and does not
allow runtime switching.

Only one operational command runs at once, but SSO traffic and approvals keep
flowing while it runs. Without a TTY, use one-shot `exec` mode (parent options
come first):

```bash
truapi-host signing-host exec '/session'
truapi-host signing-host --auto-accept exec '/script ./js/scripts/ring-vrf-smoke.ts'
truapi-host signing-host exec '/pair polkadotapp://pair?handshake=...'
```

`exec` does not enable raw mode or emit terminal controls. Command results go
to stdout, diagnostics go to stderr, and the process exits when the command
finishes. Starting `signing-host` without `--script` or `exec` while either
stdin or stdout is not a TTY is an invocation error. The existing `--script`
one-shot mode remains supported.

## Writing a product script

A product script is top-level JavaScript or TypeScript (an ES module) run by
Bun. It can import npm dependencies available beside the script or in a parent
project. The runner injects three globals before running it:

- **`truapi`** — the `@parity/truapi` client connected to the pairing host and
  scoped to the host's `--product-id`. Call `truapi.account.requestLogin(...)`,
  `truapi.signing.signRaw(...)`, `truapi.localStorage.write(...)`, etc.
- **`host`** — just `host.productId` and `host.productAccount(index?)`. That is
  all it does: it keeps product accounts in sync with the host's `--product-id`
  (hardcoding a mismatched id fails signing with `PermissionDenied`). Use
  `console.log` and `throw` for everything else.
- **`assert`** — throw when its condition is false, using any following values
  as the error message.

Write it top-level and `throw` (or reject) to fail the run:

```ts
const login = await truapi.account.requestLogin({ reason: undefined });
if (
  !login.isOk() ||
  (login.value !== "Success" && login.value !== "AlreadyConnected")
) throw new Error("login failed");

const res = await truapi.signing.signRaw({
  account: host.productAccount(),
  payload: { tag: "Bytes", value: { bytes: "0xdeadbeef" } },
});
res.match(
  (v) => console.log("signature", v.signature),
  (e) => { throw new Error(JSON.stringify(e)); },
);
```

`--product-id` (a dotNS name ending in `.dot`, `.paseo` or `.test`, or a
`localhost` identifier; default
`headless-playground.dot`) sets the initial product. `/product <id>` changes it
for the lifetime of the process. Switching disconnects active product
WebSockets so clients reconnect with a new product context; the network,
pairing relationship, signing-host session, and wallet identity stay active.
Product-owned storage, permissions, and derived product accounts are scoped by
the selected id, so the newly selected product sees its own state. The next
`/script` also receives the new id through `host.productId`.

Pairing-host state follows the same identity rule under
`<base-path>/<network>/<username>_pairing_host`. Before the first identity is
known it uses the small `<network>/pairing-host` bootstrap; connecting moves
legacy bootstrap data to the first resolved user. After `/logout`, connecting
as a different user swaps to that user's KV/core namespace instead of carrying
the previous user's product data forward.

Product-local KV is persisted independently under each identity root as
`storage/<safe-product-slug>--<hash>.json`. Each document records its normalized
product id and raw product keys. On first use, the older combined
`product-storage.json` in that profile is split into those files and retained
as `product-storage.v1.json.migrated`. Product and core JSON writes use a
flushed temporary file and atomic rename.

Six scripts ship under `js/scripts/`:

- `battery.ts` — the generated full-surface gate. It discovers every method
  from the same code-generated example manifest as the playground Diagnosis,
  attempts all examples (including APIs the browser diagnosis classifies as
  intentionally unsupported), prints test-reporter rows with timings and clean
  failure details, writes the browser-shaped result matrix to
  the role-specific report under `explorer/diagnosis-reports/spa/`, and exits
  nonzero if any example fails. A paired run writes `pairing-host-cli.md`; a
  direct signing-host run writes `signing-host-cli.md`. Override the artifact
  path with `TRUAPI_BATTERY_REPORT_PATH`.

  On top of the generated examples it runs one hand-written
  `Resource Allocation/auto_signing_e2e` case: allocate `AutoSigning`, then
  prove through the hosts' consulted-approval transcript
  (`TRUAPI_APPROVALS_LOG`, exported per phase by `scripts/battery.sh`) that
  follow-up `sign_vrf` calls for the granting product run without a
  confirmation prompt.

  `scripts/battery.sh` at the repo root is the supported entry point. It
  prepares the codegen output and playground dependencies the battery imports,
  builds the host from source, and produces both reports in one invocation: the
  direct signing-host phase, then the paired phase, where it starts a pairing
  host, reads the `polkadotapp://pair?...` link out of its transcript, and
  answers it with a second signing host using the same product id and forwarded
  host flags so the battery can complete:

  ```bash
  scripts/battery.sh                    # both phases
  scripts/battery.sh --signing-host     # direct phase only
  scripts/battery.sh --pairing-host     # paired phase only
  make e2e-signing-cli                  # direct phase only
  make e2e-pairing-cli                  # paired phase only
  make e2e-chat-cli                     # chat phase only
  scripts/battery.sh --release          # release binary
  scripts/battery.sh -- --network foo   # arguments after `--` go to every host process
  ```

  `BATTERY_PHASE_TIMEOUT` (default 900s) bounds each phase and
  `BATTERY_PAIRING_TIMEOUT` (default 120s) bounds the wait for the pairing link.
  Per-phase host transcripts land in `target/battery/`.

  The paired phase gives its pairing host a throwaway `--base-path` under
  `target/battery/pairing-host-state`, so it performs a real handshake on every
  run. A pairing host that restores an earlier session reports
  `AlreadyConnected` and then fails every remote example, because the signing
  host that session was paired with is no longer running. The signing host keeps
  the default base path and reuses its attested account.

  To drive the paired topology by hand instead, start the pairing host and
  answer its emitted link from a second terminal:

  ```bash
  # Terminal 1
  cargo run -p truapi-host-cli -- pairing-host \
    --product-id truapi-playground.dot \
    --script rust/crates/truapi-host-cli/js/scripts/battery.ts \
    --auto-accept

  # Terminal 2
  cargo run -p truapi-host-cli -- signing-host \
    --deeplink '<pairing link>' \
    --auto-accept
  ```

- `whoami.ts` — calls `getUserId` and prints `WHOAMI <primary username>`; this
  remains available as an explicit `/script <path>` example.
- `signing-smoke.ts` — a focused product-account signing check.
- `smart-contract-allowance-smoke.ts` — requests a PGAS allowance for product
  account index 0. Reports `Allocated` against `paseo-next-v2`; a host that serves
  no Asset Hub role reports `NotAvailable` rather than failing. The direct path asks
  for `Increase`, so each run submits a real claim and spends one of the day's slots
  rather than noticing the account is already funded: repeat runs within a day can
  exhaust them and then fail for that reason rather than a regression. The host logs
  the real cause, which the wire value flattens to `NotAvailable`.
- `ring-vrf-smoke.ts` — registers and lists an explicit RFC-0024 key, derives
  its alias, verifies a fresh non-member key returns `NotMember` for a proof,
  and exercises direct ring-VRF signing.
- `preimage-smoke.ts` — a focused Bulletin preimage flow check.

The generated examples are baked to the `truapi-playground.dot` product. With
live routing enabled, `Chain/stop_transaction` uses host-owned operation ids and
treats already-finished provider operations as stopped. `Preimage/*` also uses
the real Bulletin Next chain and asks the signing host to claim People-chain
long-term storage before returning the product-scoped Bulletin allowance key.
It needs the playground's deps (`cd playground && yarn install --frozen-lockfile`;
bun does not resolve the `link:` dependency on `@parity/truapi`). Repeated live
runs can exhaust the signer's per-period Statement Store or Bulletin allocation
slots. Statement Store registration replaces the oldest slot whose replacement
cooldown has elapsed, so exhaustion needs every slot to be within that
cooldown; the signing host rotates auto-managed signer accounts if that
happens.

## Confirmations

Both hosts take `--auto-accept`. Without it, confirmations a web/iOS host would
show as a modal (sign requests, permission prompts, and cross-product Ring-VRF
requests) are rendered prominently in the signing-host transcript and answered
directly with `y` or `n` (typed `yes`/`no` plus Enter also works). Approval
cards summarize and redact signing payloads rather than dumping debug objects.
The current command draft is
restored afterward; Esc safely rejects. Concurrent approvals are serialized.
In non-interactive `exec` mode, a TTY gets a plain yes/no prompt and non-TTY
stdin safely rejects instead of hanging. Same-product Ring-VRF requests do not
prompt, matching the iOS signing host. Pass `--auto-accept` for unattended
runs; every auto-approved decision is still printed.

## Logging

Use the global `--log-level` option (`error`, `warn`, `info`, `debug`, or
`trace`) before or after the subcommand, or `/log <level>` in the terminal UI.
Every decoded inbound SSO request and every published response is visible
regardless of the selected level. Stable response entries include the request
name, statement and remote message ids, protocol outcome, and elapsed time;
encoded protocol errors include their reason. Response-publication failures
are shown separately. `debug` adds decoded request/response summaries and
`trace` adds complete payload and transport metadata. Undecodable requests are
warnings with the available identifiers so protocol-version mismatches can be
diagnosed.

```bash
truapi-host signing-host --log-level trace --deeplink '<deeplink>' --auto-accept
```

Debug and trace output may contain product signing payloads. `RUST_LOG` takes
precedence at startup and remains available for module-specific filters, except
that the noisy `rustls` and `tungstenite::protocol` tracing targets are always
excluded from CLI log output. Without `RUST_LOG`, `--log-level` and `/log`
apply to TrUAPI targets while other third-party dependencies remain at `warn`.

## Statement-store allowance

The real statement store enforces per-account allowance. Before pairing, the
signing host grants it on-chain exactly as a real client does: it proves its
personhood ring membership with a bandersnatch ring-VRF and submits an unsigned
General (v5) `Resources.set_statement_store_account` extrinsic for each account
that submits statements — its RFC-0022 `uid.dot` identity account and the
pairing host's per-pairing device key. The shared native implementation lives in
`truapi-server/src/runtime/statement_allowance/` (metadata-driven
signed-extension encoding, ring fetch, slot scan, ring-VRF proof, extrinsic
assembly, submit). The signing account must be an attested member of at least
one personhood collection, and may sit in an old ring, so the signing host scans
back from the current ring index (slow, one-time per pairing).

Each collection is a separate alias space with its own budget, so a signer with
full personhood has `StmtStoreSlotsPerPeriod` slots in `People` on top of
`LiteStmtStoreSlotsPerPeriod` in `LitePeople`. Asset Hub budgets PGAS claims the
same way, through `Pgas.MaxClaimsPerPeriodPerPerson` and
`MaxClaimsPerPeriodPerLitePerson`, and a claim is scanned against the budget of
the collection it is proved against. A PGAS claim proves one collection rather
than pooling across both, so it is bounded by that collection's budget alone.

Registration pools across every collection the signer can prove, and a free slot
anywhere is taken before any live slot is replaced. Whether a live slot may be
replaced at all depends on the caller. The renewal pass, the pairing-time grant,
and `alloc-check --submit` may replace, and then take the globally oldest
replaceable slot across all collections. Allocation on behalf of a connecting
product may not: it reports the period as exhausted, because every entry in the
table is one of this wallet's own products and reclaiming space belongs to the
renewal pass. `alloc-check` prints both collections' member keys, ring indices and
slot tables. Auto-managed accounts are stored in
`accounts.json` under `--base-path`; mnemonics are plaintext local test secrets
and the file is written with `0600` permissions on Unix. `alloc-check` verifies
membership and can submit a test registration.

## Manual use (two terminals)

```bash
make headless install

# Terminal 1 — pairing host runs a product script and prints its pairing link:
truapi-host pairing-host --product-id myapp.dot --script js/scripts/battery.ts --auto-accept

# Terminal 2 — hand the deeplink to a signing host (registers allowance, signs).
# The wallet mnemonic comes from --mnemonic / $HOST_CLI_SIGNER_MNEMONIC when set;
# otherwise the CLI auto-selects or creates an attested account.
truapi-host signing-host --deeplink '<deeplink>' --auto-accept
HOST_CLI_SIGNER_MNEMONIC="spin battle …" truapi-host signing-host --deeplink '<deeplink>' --auto-accept

# Inspect on-chain statement-store allowance for a mnemonic:
truapi-host alloc-check --mnemonic "spin battle …" --lookback 100
```

Both hosts take `--network`, either `paseo-next-v2` (default) or `previewnet`.
The network preset owns the identity backend URL, the People, Bulletin and Asset
Hub RPCs, and their genesis hashes; there is
no public `--statement-store` flag. Pick `previewnet` when a product's runtime
descriptors target previewnet, so its statements, its host chain routes and its
own chain reads all land on one network. The CLI mints the identity backend's
bearer token itself (SPEC.md §12.3). Sessions are per preset, so each network
gets its own signer identity on the same machine.
`HOST_CLI_IDENTITY_BACKEND_BASE` swaps only
the identity backend (for a local one); `HOST_CLI_IDENTITY_BACKEND_TOKEN`
supplies its bearer token instead of the CLI minting one. For username
registration, an injected token's subject must match the session's `uid.dot`
candidate account. The automatically minted token uses that identity; and
`HOST_CLI_DOTNS_POP_CONTROLLER` overrides on-chain `DotnsPopController`
discovery (see SPEC.md §21). Both also accept `--frame-listen <address>`
to opt into a TCP product-frame WebSocket; without it, the CLI creates and
cleans up a unique temporary Unix socket.

## Serving a dev server (one process, no terminal)

`signing-host --serve` runs the host as a background service instead of a
terminal UI, so a dev server or test harness can supervise it:

```bash
truapi-host signing-host --serve \
  --frame-listen 127.0.0.1:9955 \
  --product-id myapp.dot \
  --auto-accept
```

It needs no TTY, initialises the signer, and stays up until stopped. Output is
one line per event:

```
✓ Paired with headlessyvqhet.43
✓ Signing host ready
• Listening for product frames
  ws://127.0.0.1:9955
• Serving product frames until stopped
  ws://127.0.0.1:9955
  Confirmations are approved automatically
```

Wait for `Serving product frames until stopped` before pointing a product at the
endpoint. That line is last in every case, and it is the only one that means
both halves are up: the frame socket accepts connections well before a signer
exists, and `Signing host ready` can arrive either side of it depending on
whether the session was cached or is being registered. A first run registers a
lite username and the statement-store allowance on-chain, which can take
minutes.

Stopping it: Ctrl-C is handled, so the host logs its own shutdown. `SIGTERM`
ends the process, which is what a supervising dev server sends.

`--auto-accept` is effectively required, because a process with no terminal has
nowhere to prompt: confirmations are denied instead, and the startup line says
so. `--serve` cannot be combined with `--script` or `exec`, which are the
one-shot modes.

## Scope / gaps

- **Chain methods** route to real `wss://` nodes from the selected `--network`.
  Every role the preset serves is routed unconditionally; `E2E_LIVE_CHAIN=1` only
  widens routing to endpoints it carries without serving. A rustls crypto provider is
  installed at startup for the TLS connections.
- **Ring-VRF product-account aliases and proofs** are implemented by the
  signing host via the `verifiable` crate (`get_account_alias` and
  `create_account_proof`).
- **`get_user_id`** resolves the signing account's username from the dotNS
  contracts on Asset Hub. Auto-managed signing accounts register fresh lite
  usernames via the identity backend (`src/attestation.rs`); first registration
  is backend-async and can take minutes (ring onboarding). `truapi-host
  identity-check --mnemonic <m>` probes which derivation carries a username.
- `set_statement_store_account`, Bulletin long-term-storage, and Asset Hub PGAS
  resource allocation are implemented over SSO on native headless hosts.
- Everything else the browser host exercises passes: signing (raw, payload,
  create-transaction, and their legacy variants), statement store, entropy,
  aliases, preimage, storage, permissions, notifications, theme, system, chain
  and user id, subject to live chain availability
  and allowance-slot capacity.
