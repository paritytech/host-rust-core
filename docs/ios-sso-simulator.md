# iOS SSO simulator runbook

Use this runbook to validate the shared Rust SSO responder inside
`polkadot-app-ios-v2` against `truapi-host pairing-host`. These details were
confirmed with an iOS 18.3.1 simulator and the Paseo Next v2 test network.

## Build the Rust library first

The Xcode project links the already-built simulator archive. Rebuild it after
every Rust core change or Xcode can succeed while embedding stale Rust code.

```bash
# repository root
cargo build -p truapi-server \
  --release \
  --features ws-bridge \
  --target aarch64-apple-ios-sim
```

## Build the correct iOS flavor

Use an arm64 iOS 18.3 simulator and the Nightly/Paseo flags. A plain Debug
build selects PreviewNet and cannot pair with a CLI using `paseo-next-v2`.
The iOS 26 simulator exposed unrelated keychain/onboarding failures during
this flow, so it is not the reference test device yet.

```bash
IOS_SSO_SIMULATOR_ID=<simulator-udid>

cd hosts/ios
xcodebuild \
  -project polkadot-app.xcodeproj \
  -scheme polkadot-app \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${IOS_SSO_SIMULATOR_ID}" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  TRUAPI_SWIFT_FLAGS='-DF_DEV -DNIGHTLY -DTESTNET_FEATURE -DIOS_PASEO_E2E' \
  build
```

Do not set `CODE_SIGNING_ALLOWED=NO`: that produces an app the simulator will
not launch. The Xcode pre-actions run SwiftFormat across the checkout; inspect
`git status` afterward and restore formatting-only changes outside the files
you intentionally edited. Do not pipe `xcodebuild` through `tail` or a similar
filter while automating this run: the wrapper can return while the underlying
build still owns `XCBuildData/build.db`, making the next invocation fail with
“database is locked”. Use the unpiped command (optionally with `-quiet`) and
wait for its exit status.

Install the resulting signed Debug app:

```bash
IOS_SSO_APP_PATH=<derived-data-path>/Build/Products/Debug-iphonesimulator/polkadot-app.app
xcrun simctl install "$IOS_SSO_SIMULATOR_ID" "$IOS_SSO_APP_PATH"
xcrun simctl launch "$IOS_SSO_SIMULATOR_ID" io.pcf.polkadotapp.develop
```

## Prepare a real iOS identity

Recover or create a disposable RFC-0022 test wallet and make sure its `uid.dot`
identity plus `peopl.dot` LitePeople membership are registered on Paseo Next
v2 before importing the same mnemonic into the app. A wallet claimed through
the older native `//wallet` flow is not an RFC-0022 test identity and will fail
alias, proof, allowance, and legacy-identity signing checks even when the
shared core is working correctly.

All hosts use the same RFC-0022 derivations. `platformType` is metadata only;
it must never select account, ring-VRF, allowance, or ECDH key material.

On a fresh simulator, the app can remain on “Waiting for network connection”
until Safari has made the simulator's first network request. Open any HTTPS
page once, then relaunch the app.

## Pair the CLI

The Debug app registers `polkadotappdev://`, while the CLI prints the
production `polkadotapp://` deeplink. Replace only that scheme before opening
the deeplink in the Debug simulator. The app accepts both schemes when parsing
the handshake.

Use `truapi-playground.dot` for the generated battery. Using
`headless-playground.dot` makes the signing examples request the wrong product
accounts and produces misleading permission failures.

```bash
./target/debug/truapi-host pairing-host \
  --base-path /tmp/truapi-ios-pairing-host-e2e \
  --network paseo-next-v2 \
  --product-id truapi-playground.dot \
  --auto-accept \
  --log-level info \
  --script rust/crates/truapi-host-cli/js/scripts/battery.ts
```

Approve the sensitive operations in the simulator. The supported baseline is
46 passing examples. The remaining 19 examples are the currently unwired Chat
(6), Coin Payment (9), and Payment (4) service families.

## Recover a simulator without erasing it

If temporary onboarding defaults were injected, remove them through the
simulator's `cfprefsd` domain before relaunching. Editing or inspecting the
preferences plist directly is not authoritative while `cfprefsd` is running.

```bash
xcrun simctl terminate "$IOS_SSO_SIMULATOR_ID" io.pcf.polkadotapp.develop
xcrun simctl spawn "$IOS_SSO_SIMULATOR_ID" \
  defaults delete io.pcf.polkadotapp.develop username
xcrun simctl spawn "$IOS_SSO_SIMULATOR_ID" \
  defaults delete io.pcf.polkadotapp.develop usernameClaimed
xcrun simctl spawn "$IOS_SSO_SIMULATOR_ID" \
  defaults delete io.pcf.polkadotapp.develop isPerson
xcrun simctl launch "$IOS_SSO_SIMULATOR_ID" io.pcf.polkadotapp.develop
```

Use `xcrun simctl spawn "$IOS_SSO_SIMULATOR_ID" defaults read
io.pcf.polkadotapp.develop` when diagnosing those values. If the app reports
“Environment has been reset”, clear injected values and use the app's Start
Over/recovery flow rather than adding more defaults.

## Failure signatures

- `BlockHeaderNotFound` during alias/proof means the native JSON-RPC engine
  advertised ChainHead but did not return the finalized header. The Rust ring
  resolver falls back to legacy `chain_*`/`state_*` RPC for this snapshot.
- `channelPriorityTooLow` on the second rapid SSO request means two statements
  reused an expiry priority. Rust statement priorities are process-locally
  monotonic so calls created in the same second remain strictly ordered.
- A legacy signer “not available in this CLI wallet” means the requested
  account is not the RFC-0022 `uid.dot` identity derived from the active root
  entropy. Check that the simulator imported the RFC-provisioned mnemonic.
- A ten-second timeout after approving VRF is a CLI diagnosis timeout, not a
  cryptographic failure. Interactive SSO methods use the remote-response
  timeout in the battery runner.
