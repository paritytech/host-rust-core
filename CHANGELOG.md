# Changelog

All notable changes to the TrUAPI protocol are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
generated from [Conventional Commits](https://www.conventionalcommits.org/).

## [0.12.0] - 2026-08-31

### Added

- `development_createAccountProof` for raw proof contexts to unblock Humanity as a Product (#457)
- open bump issues on consumer repos when a package is released (#529)

### Changed

- RFC: Host locale subscription (#526)
- fix prebuilt script runner lookup (#532)

### Fixed

- reject unknown wire messages (#547)
- declare the chat worker in the product manifest (#541)
- downgrade response and error payloads to the caller's version (#525)

## [0.11.0] - 2026-08-27

### Added

- prebuilt truapi-host binaries, one-liner installer, and self-update (#516)
- local dev flow — run a product in a browser tab against the CLI host (#510)
- revalidate device permissions against OS state before use (#471)
- expose current product context (#504)
- publish io.parity:truapi-host-android as an AAR (#337)
- auto-grant remote permissions to trusted product labels (#446)
- improve signing-host session lifecycle (#495)

### Changed

- @parity/truapi 0.11.0, @parity/truapi-host 0.8.0 (#530)
- remove legacy single-execution core (#508)
- RFC: Host Identity and Version via `System.host_info` (#177)

### Fixed

- make the CLI release pipeline work end to end (#531)
- clear the sandbox client when the pipe closes (#509)
- persist and restore paired SSO hosts (#501)
- gate tags on a confirmed npm publish (#505)
- derive Pages base path from configure-pages (#500)

## [0.10.0] - 2026-08-24

### Added

- match manifest execution kinds and serve custom chat rendering from a JS host (#459)
- gate WebRTC on a decision resolved before the product realm (#444)
- let a host read what the last renewal pass achieved (#447)
- tell a listener which way its connection closed (#461)
- forward every message variant and add the Android host surface (#453)
- serve product frames headlessly with --serve (#439)
- export createWebSocketProvider for browser clients (#438)
- add the previewnet network preset (#440)
- serve Chat from a JS host as an optional capability (#400)
- implement Chat::register_bot in the shared Rust core (#430)
- native and wasm ChainProvider with WebSocket and embedded smoldot backends (#276)
- retain and expose session identity material (#403)
- gate external navigation on a per-host remote grant
- give AuthState::LoginFailed a typed kind (#401)
- pool allowance slots across personhood collections (#431)
- report renewal targets dropped by an identity change (#423)
- drive statement-store allowance renewal from native hosts (#417)
- yield the named theme from subscribe_theme (#396)
- serve Asset Hub as a chain role (#404)
- support PGAS allowances (#391)
- make ProductContext SCALE-encodable (#392)

### Changed

- @parity/truapi 0.10.0, @parity/truapi-host 0.7.0 (#494)
- Own-account subtree consent gate, deadline bound, and worker dispose fix (#469)
- Person's usernames: read from Asset Hub dotNS instead of the People Chain (rebase of #349) (#426)
- publish 0.7.0 (#450)
- SSO message handling bindings for Mobile hosts (#433)
- Allow webrtc connection for products (#399)
- update Package.swift (#421)
- Add product manifest RFC and host implementation guide

### Fixed

- raise the crate recursion limit for the trait solver (#475)
- accept the test dotNS TLD in product identifiers (#465)
- follow previewnet through its wipe (#455)
- stop a product or host from aborting the process (#452)
- track tunnel liveness by flag, not by dialling (#445)
- satisfy collapsible_match without changing Enter handling (#437)
- narrow the navigation grant to authorizable hosts
- satisfy collapsible_match without changing Enter handling
- advertise the People genesis the chain reports (#416)
- emit the opening auth state and forward session activation (#393)
- resolve product chains against the network preset (#402)
- import the wasm glue by a literal specifier (#394)
- skip v5 signing for supplied VerifyMultiSignature (#374)
- encode the transaction-extension version the runtime declares (#382)

## [0.9.0] - 2026-08-13

### RFCs

- **Accepted:** Proof of Personhood as a product

### Added

- replace the oldest slot when a period is full (#378)
- auto-renew statement-store allowances (#308)
- land RFC-0024 ring VRF key management (#360)

### Changed

- @parity/truapi 0.9.0, @parity/truapi-host 0.6.0 (#381)
- share one extension-info resolver in allowance metadata (#377)
- stop re-reading metadata and rings on every allowance call (#366)
- update ios library to 0.5.0 (#367)

### Fixed

- accept per-network dotNS TLDs in product identifiers (#369)
- deploy the playground under the new dotNS name format (#375)

## [0.8.0] - 2026-08-10

### RFCs

- **Accepted:** Host chain discovery and name resolution

### Added

- implement chain.getChainInfo in the core (#358)
- integrate the Chat modality with the shared Rust core (#326)
- support Extrinsic V5 transaction signing (#333)
- export parse_navigate to native hosts (#340)

### Changed

- @parity/truapi 0.8.0, @parity/truapi-host 0.5.0, @parity/ios-host 0.5.0 (#364)
- RFC 0026: Host chain discovery and name resolution (#354)
- Use canonical types over the native FFI (#345)
- iOS host integration (#330)

### Fixed

- isolate RFC-0022 session and AutoSigning capabilities (#329)

## [0.7.0] - 2026-08-04

### Added

- complete RFC-0022 host cutover (#327)

### Changed

- @parity/truapi 0.7.0, @parity/truapi-host 0.4.0 (#332)

## [0.6.0] - 2026-07-31

### RFCs

- **Accepted:** Account key derivations
- **Accepted:** sr25519 VRF signing for product accounts

### Added

- Android host adapter (android/truapi-host) + hosts/android submodule (#289)
- implement missing signing host fn (#288)

### Changed

- @parity/truapi 0.6.0, @parity/truapi-host 0.3.0 (#325)
- RFC 0023 - Sign VRF (#301)
- RFC 0022: Account key derivations (#296)
- cli host (#264)
- iOS host (#215)
- adopt Send async traits (#312)
- @parity/truapi-host 0.2.1 (#320)

### Fixed

- recheck inclusion instead of re-broadcasting on watch stop (#307)
- stop the broadcast operation returned by host (#318)

## [0.5.1] - 2026-07-21

### Changed

- @parity/truapi 0.5.1 (#302)

### Fixed

- run products on legacy hosts (#300)

## [0.5.0] - 2026-07-20

### RFCs

- **Accepted:** RFC 0004 — Redesign `host_account_create_proof`

### Changed

- @parity/truapi 0.5.0, @parity/truapi-host 0.2.0 (#293)
- RFC: Redesign RingLocation in host_account_create_proof (#18)

### Fixed

- cover Dotli signing regressions (#291)
- prevent stale generated bindings (#287)

## [0.4.1] - 2026-07-16

### Changed

- @parity/truapi 0.4.1 (#284)
- @parity/truapi-host 0.1.0 (#278)

### Fixed

- treat Firefox's masked "null" ancestor origin as hidden (#283)
- updates in diagnosis report + submit report button (#277)
- create tags through API (#282)
- unblock post-merge workflows (#281)

## [0.4.0] - 2026-07-15

### RFCs

- **Accepted:** Coinage Payment User Agent API

### Added

- build, sign, and submit Bulletin preimages in the core (#270)
- add @parity/truapi-host-wasm runtime (#252)
- generate wasm bridge callbacks (#265)
- add platform runtime and host bridge (#250)
- add wire and chain infrastructure (#256)
- add host logic primitives (#255)
- emit Rust dispatcher, wire table, and host callbacks (#254)
- add host capability traits (#249)
- add testing API and versioned wiring (#248)
- add explorer 0.3.2 version snapshot (#242)

### Changed

- @parity/truapi 0.4.0 (#279)

## [0.3.2] - 2026-06-26

### RFCs

- **Withdrawn:** Extended theme subscribe API

### Added

- add @parity/truapi/sandbox bootstrap entry point (#234)
- add explorer 0.3.1 version snapshot (#231)
- version lifecycle tooling (#145)

### Changed

- @parity/truapi 0.3.2
- @parity/truapi 0.3.2
- Playground e2e harness + SCALE codec additions (#238)
- rename Provider type to WireProvider (#235)
- Update diagnosis compatibility statuses (#233)
- Update playground transaction example for DotNS signer (#220)
- Revert "ci: remove redundant build skip env"
- fix
- Bump the actions group with 11 updates (#199)
- Add explorer v0.3.0 version snapshot
- Delete zizmor logs
- Apply zizmor --fix=all
- Preserve logs on timeout, float copy button, hide editor line numbers
- Annotate subscribe example statement and export generated types in Monaco dts
- Drop diagnosis-report changes; keep only the Rust example fixes
- Fix statement-store subscribe example and multi-line diagnosis details
- update ios report (from #189)
- route type-page links through typePath helper
- update ios report (from #182)
- update android report (from #180)
- update web report (from #178)
- update desktop report (from #175)
- improve examples
- fix
- fixes
- fixes
- fixes
- fixes
- fixes
- tmp
- test
- bundle the static export into a handful of chunks
- ss updates
- drop per-run report timestamp; fix docs
- Drop the per-method cancellation feature
- Cancel a processing diagnosis method from the UI
- Submit diagnosis reports via a pre-filled GitHub issue

### Fixed

- use GitHub API to create release tag
- align HostPaymentTopUpError SCALE indices with triangle-js-sdks (#223)
- Simplify the diagnosis run and fix the statement-store submit example (#174)
- remove version bump from cut-version.sh

### Removed

- roll back the CoinPayment (Coinage) host API

## [0.3.1] - 2026-06-17

### Changed

- @parity/truapi 0.3.1 (#228)
- @parity/truapi 0.3.1
- @parity/truapi@0.3.0
- @parity/truapi@0.3.0
- Revert "Add explorer v0.3.0 version snapshot"
- Add explorer v0.3.0 version snapshot

### Fixed

- use GitHub API to create release tag
- correct import paths in explorer 0.3.1 snapshot
- align HostPaymentTopUpError variant ordering with wire protocol
- add MIT license field to workspace and all crates
- remove prepare hooks and add deny.toml from main
- remove prepare hook from truapi-host package

## [0.3.0] - 2026-06-03

### RFCs

- **Accepted:** RFC-0020: Remove `context` from `create_transaction` and mirror in Accounts Protocol
- **Accepted:** Add Coins variant to PaymentTopUpSource
- **Accepted:** Extended theme subscribe API
- **Withdrawn:** Host API root account access
- **Withdrawn:** Simple Group Chat

### Added

- append to matrix instead of override
- extend theme subscribe API with named themes
- proc-macro envelopes + conversion traits
- add Next variant to Version enum
- diagnosis screen + host compatibility matrix (#143)
- show method examples and deep-link to the hosted playground
- require a ```ts example on every trait method
- add version lifecycle tooling and next/ staging module
- host compatibility matrix page
- codegen-driven explorer site with version snapshots (#130)
- implement RFC-0020 Rust types for create_transaction
- add host-side codegen and @parity/truapi-host package (#77)

### Changed

- Use Sr25519 secret keys in PaymentTopUpSource
- Always rebuild the compatibility matrix from the reports alone
- Regenerate compatibility matrix: drop skipped Coin Payment, restore host order
- fix
- fix
- update
- fixes
- Add 'make explorer' to run the explorer dev server locally
- update
- Add 'make matrix' to regenerate the compatibility matrix
- Track per-host diagnosis reports in version control
- update diagnostics
- one at a time
- clean up
- fixes
- improved errors
- update dotli sha
- Replay diagnosis methods and streamline the report action
- auto-test removal
- Add report error column, raise unary timeout, mark Signing/create_transaction web pass
- Expand diagnosis failures, link method breadcrumb to the index
- Deep-link diagnosis, fix host-mode detection, use chain const in signing examples
- improve playground ux
- fix up
- fix up compatibility tests
- @parity/truapi 0.3.0
- cut v0.3.0
- fix
- reduce payment
- IOS report
- simplify matrix builder and host-mode detection
- Update report matrix with android
- Set top_up example amount to 10000
- drop redundant playground link from method example
- Add compatibility parsed reports for web and desktop
- simplify for now
- remove unused Version enum and IntoVersion trait
- update versioned types
- Update RFC index
- Specify deployment environment for Playground (#142)
- Update README references
- Parse diagnosis reports into matrix
- remove JSON-RPC from 0.2.0 snapshot
- Generate diagnosis matrix
- align spec to actual implementation
- Remove RFC 0011-simple-group-chat
- Rfc skill (#131)
- small cleanups extracted from #96 prep work (#124)
- add WELL_KNOWN_CHAINS constants, use in examples (#128)
- Remove RFC 0010-get-root-account
- Notes from 12.05 Working Group Review
- Update 0020-create-transaction.md
- Create 0020-create-transaction.md
- Add Rust trait update checklist item to RFC PR template
- Auto-number RFCs on merge via CI
- complete withChainHeadFollow on Stop instead of erroring
- scope withChainHeadFollow subscriptionId per subscription
- extract withChainHeadFollow, drop `any` from examples, fix GenericError wire
- cargo-doc: serve static.files at site root so rustdoc CSS resolves (#119)
- fall back to ancestorOrigins when referrer is empty (#120)
- sync Cargo.toml version and auto-create GitHub Release (#113)
- render offline UI on GH Pages instead of stuck splash (#118)
- Playground: Monaco editor + rxjs + cargo-doc links + deep links (#116)
- Fix wire ID collision: shift CoinPayment IDs to 136+
- Rename listen_for to listen_for_payment
- RFC 0019: mark as breaking change
- Align RFC 0019 method names and error type with trait renames
- Rename push_notification methods for clarity
- Rename PushNotificationError to HostPushNotificationError
- RFC 0017: remove CoinPaymentInvoice type and align method names
- Remove version field from RFC pseudocode CoinPaymentCheque
- Fix codegen: collect error wrappers for ResultSubscription methods
- Address review comments: remove version field, error aliases, and Resolvable type
- Drop host_coin_payment_ prefix from CoinPayment trait methods
- move notification methods from System to Notifications trait
- implement RFC 0019 scheduled push notifications
- Remove unused PaymentPurse alias and CoinPaymentInvoice type
- Rename HostPaymentRequestRequest to HostPaymentRequest (#83)
- RFC 0017: add CoinPayment host API
- updated tokens with the ones from new design system

### Fixed

- match upstream ThemeName variant order (Custom before Default)
- keep version at 0.3.0 for release
- make PartialPayment top-up error a non-breaking append
- clean up cut-version.sh
- qualify method routes by service
- harden contiguity check and pin multi-version codec indices
- Update Paseo Next V2 Genesis hash
- make examples valid against the generated client
- remove unused HostCreateTransactionWithLegacyAccountRequest
- protocol document
- removed JAM codec mention
- restored indices
- display for RemotePermissionRequest
- fold RFC17 review cleanup
- rename host_push_notification_cancel to push_notification_cancel
- align CoinPayment trait with native async traits

### Removed

- roll back the CoinPayment (Coinage) host API
- remove Version::Next — unused until V2 types exist

## [0.1.0] - 2026-05-15

### RFCs

- **Accepted:** RFC Title
- **Accepted:** Permission Model for Host API
- **Accepted:** Payment Host API
- **Accepted:** RFC-0007: Deterministic Entropy Derivation for Products
- **Accepted:** Statement Store Host API v0.2
- **Accepted:** RFC-0009: Unauthenticated Product Access
- **Accepted:** RFC-0010: W3S Allowance Management in TrUAPI
- **Accepted:** Host API root account access
- **Accepted:** Simple Group Chat
- **Accepted:** RFC-0015: Get User Primary DotNS Name
- **Accepted:** Scheduled Push Notifications

### Added

- reject wire ids that collide with RESERVED_WIRE_IDS

### Changed

- @parity/truapi 0.1.0 — drop --ignore-scripts from install (#91)
- @parity/truapi-0.1.0 (#89)
- @parity/truapi-0.1.0
- Add release template
- Replace release bot with [release: PR title] gate
- Add release workflow to publish @parity/truapi via npm_publish_automation
- ignore generated TS outputs in git (#73)
- Refactor codegen (#68)
- remove public_key from HostGetUserIdResponse
- parse version from type prefix instead of hard-coding V01
- drop "0." from protocol version label
- rewrite to match actual repo structure and RFC CI requirements
- update generated types after macro doc comment changes
- address review: future-proof docs, auto-generate versioned wrapper doc comments
- drop v02 module: merge all types into v01, remove codegen discriminant hack
- tighten SubscriptionError assertions on malformed-receive and provider-close
- collapse observer error to single SubscriptionError type
- fix fmt and regenerate TS client
- Update rust/crates/truapi/src/api/calls.rs
- Update rust/crates/truapi-codegen/src/typescript.rs
- Bump next from 15.5.15 to 15.5.18 in /playground
- rename chainHeadFollow → chainHeadFollowSubscribe
- fix client example return types and regenerate
- regenerate TS client and examples
- fix legacy sign-payload example and fmt
- add V2 HostSignPayloadWithLegacyAccountRequest
- truapi-codegen: emit HexString import in generated client.ts
- add JsonRpc, Theme, ResourceAllocation traits + host_request_login
- add remote_preimage_submit + statement_store_create_proof_authorized
- add host_sign_*_with_legacy_account (wire 34–37)
- rename remote_chain_head_follow → remote_chain_head_follow_subscribe
- fix fmt
- drop host_chat_create_simple_group entirely
- move host_chat_create_simple_group off colliding wire ID 130
- emit plain HexString name + drop dead Uint8Array parsers
- update readme
- update
- align with host-product-sdk via HexString codec, drop dead helpers
- Require truapi interface changes in RFC PRs
- Add RFC validation CI workflow
- Rename deploy-playground CI file
- Fix submodule: recursive for workflows
- PR review
- simplify wire-table
- @parity/truapi: drop unused encodeWireMessage/decodeWireMessage from public surface
- rename /page diagnostics route to /diagnostics
- @parity/truapi: add publish metadata and dispose() handle
- tighten codegen and add v02 RemotePermission::PreimageSubmit
- fix ci
- fixes
- update types
- update
- fixes
- Address PR review findings
- add back doc site
- nit
- fixes
- renaming
- renaming
- rename stuff
- Address PR review findings
- updat rust code
- fix
- Fixes in RFC
- Propagate Rust doc comments to generated TS client
- Tighten review nits: deploy concurrency, BigInt regex, format args
- Pick V1 wrapper in codegen so legacy hosts decode every method
- Auto-respond to host_handshake_request in @truapi/client
- Fix handshake_response payload so the legacy decoder accepts it
- Answer the host's handshake_request to end the retry loop
- Pin handshake to V1 so legacy host-api accepts it
- Make playground reachable when no host is responding
- Add dotli submodule and top-level CLAUDE.md
- Surface subscription id; restore chain-head ephemeral-follow logic
- Add RFC 0012 for scheduled push notifications
- Promote truapi crate, add codegen, drop legacy docsite
- Add dev server proxy for legacy URL redirects
- Prepare for repo rename from truapi-explorer to truapi
- Align v0.2 API definitions with triangle-js-sdks implementation
- Migrate RFC-0014 (Get User Primary DotNS Name) as RFC-0015
- Fix TopicFilter to enum with MatchAll/MatchAny variants
- RFC-0011: Simple Group Chat
- Update RFC index with 0010-allowance entry
- RFC-0010: W3S Allowance Management in TrUAPI
- Migrate feature index and accepted RFCs from triangle-js-sdks
- Migrate PR templates and CONTRIBUTING guide from triangle-js-sdks
- Migrate host-api-protocol design doc from triangle-js-sdks
- Update Contacts API note in v02-changes.md
- Add draggable sidebar resizer with persisted width and double-click reset
- Bump vite to 8.0.8 to patch dev-server path traversal and file-read advisories
- Fix TypeScript narrowing in Fields and Variants map callbacks
- Use CSS grid for Fields and Variants tables to align columns across rows
- Fix long variant/field names overlapping right column on type pages
- Redirect legacy /host-api-explorer URLs to /truapi-explorer
- Promote v0.2 from preview to stable and make it the default version
- Update v02-changes.md with additional document links
- Add README.md
- Add Rust docs and v0.2 change doc
- Add v02 spec
- Change api-spec to v02
- Correct the vite path name
- Rename more thoroughly
- Rename host api to truAPI and add truapi-spec
- Bump brace-expansion
- Bump picomatch from 4.0.3 to 4.0.4
- Bump flatted from 3.4.1 to 3.4.2
- Make mobile friendly
- Clean up types (2)
- Clean up types
- Link types properly (2)
- Link types properly
- Improve readability
- UI improvements
- Replace iframe terminology with sandbox
- Fix GitHub Pages SPA routing
- Remove unused variable in TypesPage
- Add .npmrc to resolve Vite 8 / Tailwind peer dep conflict
- Initial commit: Host API Protocol Explorer

### Fixed

- clippy needless_borrow and stale type import

## [0.8.0] - 2026-06-01

### Added

- create transaction refinement (#168)
- experimental debug hooks across host-api, host-container, host-papp (#154)

### Changed

- 0.8 (#179)
- Rename product-sdk to host-api-wrapper (#169)

## [0.7.8] - 2026-05-11

### RFCs

- **Withdrawn:** RFC Title
- **Withdrawn:** Permission Model for Host API
- **Withdrawn:** Payment Host API
- **Withdrawn:** RFC-0007: Deterministic Entropy Derivation for Products
- **Withdrawn:** Statement Store Host API v0.2
- **Withdrawn:** RFC-0009: Unauthenticated Product Access
- **Withdrawn:** RFC-0010: W3S Allowance Management in TrUAPI
- **Withdrawn:** Host API root account access
- **Withdrawn:** RFC-0014: Get User Primary DotNS Name

### Changed

- 0.7.8 (#164)
- Add @novasamatech/product-bulletin package wrapping @parity/bulletin-sdk (#114)

## [0.7.7] - 2026-05-07

### RFCs

- **Accepted:** RFC-0014: Get User Primary DotNS Name

### Added

- sso sign methods now accept product account ID instead of SS58 address (#159)
- Implemented more web apis, simplified working with buffers (#153)

### Changed

- 0.7.7 (#162)
- 0.7.6 (#160)
- Implement rfc 10 apis (#157)
- 0.7.4 (#148)
- RFC-0014: Get User Primary DotNS Name (#144)
- 0.7.3 (#145)

### Fixed

- key derivation now matches Substrate's standard rules (#158)
- reconnects (#151)

## [0.7.1] - 2026-04-23

### RFCs

- **Accepted:** RFC Title
- **Accepted:** Permission Model for Host API
- **Accepted:** Payment Host API
- **Accepted:** RFC-0007: Deterministic Entropy Derivation for Products
- **Accepted:** Statement Store Host API v0.2
- **Accepted:** RFC-0009: Unauthenticated Product Access
- **Accepted:** RFC-0010: W3S Allowance Management in TrUAPI
- **Accepted:** Host API root account access

### Added

- add pause/resume to drop the inner socket cleanly (#140)
- add handoff-service package for P2P file transfers via HOP (#109)
- add paseo-next network and drop unstable. PB-420 (#101)
- implemented correct session initialization and batching logic (#100)
- update Paseo stable stage endpoint (#45)
- handleChainConnection now supports transaction submit permission check (#97)
- add configurable destroyDelay to connection pool (#96)
- remove withPolkadotSdkCompat usage, added enhanceBranch option to branched provider instead (#91)
- add withSubscriptionReplay provider enhancer (#89)
- add worker-sandbox package. PB-333 (#71)
- papp secret storage reexport (#76)
- implement chain connection PB-332 (#69)
- RFC/features by .md files (#57)
- make logger configurable (#19)
- add Paseo stable stage endpoint (#43)
- product-react-renderer package with chat adapter integration (#38)
- added rate limiter. PB-192 (#20)
- support updated statement store api (#33)
- update stable stage endpoints (#29)
- save session only after attestation (#24)
- 0.6.0 (#22)
- implement chain JSON RPC methods (#17)
- changes for 0.5 release (#16)
- added a disconnect attempt and an error toast. PB-118 (#15)
- update sdk to 0.5 spec (#13)
- add tr-ui, PairingPopover and theme support (#10)
- added clearAll method to localStorageAdapter (#11)
- retry auth requests, add tests (#12)
- chat (#9)
- host api spec (#7)
- Support new statement store errors while submitting statements (#8)
- Implemented correct Polkadot app pairing ui (#6)
- papp integration (#5)
- new package names, removed shared package
- Support createTransaction interface
- connection status listening

### Changed

- RFC-0010: W3S Allowance Management in TrUApi (#129)
- 0.7 (#113)
- 0.6.18 (#132)
- RFC: Statement store Host API changes according to v0.2 discussion (#118)
- RFC-0006: Payment Host API (#94)
- 0.6.15 (#102)
- 0.6.10 (#87)
- 0.6.9 (#85)
- 0.6.7 (#77)
- Release/0.6.6 (#60)
- release 0.6.5 (#35)
- release 0.6.5 (#34)
- release 0.6.4 (#32)
- 0.6.1 (#30)
- Initial commit

### Fixed

- send JSON-RPC unsubscribe on subscription teardown (#111)
- buffer request statements to prevent race condition in waitForRequestMessage (#119)
- attestation service now listens to the best block instead of finalized (#116)
- close MessagePort on provider dispose PB-310 (#78)
- disable papp ws heartbeat timeout (#70)
- qr styles (#59)
- add hostMetadata to sign-in payload. PB-293 (#37)
- correct error message for unknown signing error (#36)
- address normalization in sso sessions sign requests (#31)
- chain connection sharing across products (#21)
- added Preview People Chain (#14)
- pairing ui logos and texts
- Explicitly set account type to sr25519 in extension injector
- simplified createTransaction codec
- code style
- node versions in github action
- husky config

