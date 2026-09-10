# Building, configuring & publishing

This guide explains how to configure the app, sign it, and distribute it to
**TestFlight** and **Firebase App Distribution**.

> This repository ships a **default CI/CD setup**: GitHub Actions workflows
> (`.github/workflows/`) driven by Fastlane lanes (`fastlane/`) — see §10. It is
> preconfigured for the upstream project, so a fork must supply its own secrets,
> `match` signing repo, and runners before it runs green. Sections 5–9 document
> the underlying Apple/Google tooling the pipeline automates, so you can also
> build, sign and distribute by hand or port the flow to another CI system
> (GitLab CI, Bitrise, Xcode Cloud, …).

---

## 1. How configuration works

A small number of build-time secrets are externalised into **environment
variables** that are baked into the app at build time. Most backend endpoints
come from Firebase Remote Config instead (see `RemoteAppConfig`). There are
three pieces:

| File | Committed? | Purpose |
|------|-----------|---------|
| `Runscripts/generate_secrets.sh` | ✅ yes | Generates the Swift below from `env-vars.sh` / the environment. |
| `polkadot-app/env-vars.sh` | ❌ gitignored | Your secrets. Created from `env-vars.template.sh`. |
| `polkadot-app/Generated/Secrets.generated.swift` | ❌ gitignored | Generated Swift (`enum GeneratedSecrets`) read by the app. Produced by `generate_secrets.sh`. |

Resolution order (highest priority first): **`env-vars.sh` → the process
environment**. Any value left unset becomes an empty string, which simply
disables the corresponding feature. The app therefore builds and runs with safe
public defaults even with no secrets configured.

The **"Generate Secrets"** Xcode build phase runs `generate_secrets.sh`
automatically on every build (it is skipped when `RUN_IN_CI=true` — see the CI
note below), so you rarely need to run it by hand.

### First-time local setup

```bash
./Runscripts/setup-secrets.sh
```

This scaffolds `env-vars.sh` and the `GoogleService-Info` plists from their
`*.template` files (without overwriting anything that already exists) and
generates `Secrets.generated.swift`. The app then builds and runs; features that
need a real secret stay disabled until you provide one.

> **In CI:** set `RUN_IN_CI=true` (which skips the in-Xcode generation and the
> Google-plist copy), export the variables directly into the job environment
> from your secret store, and run `./Runscripts/generate_secrets.sh` before
> building. Provide the active `GoogleService-Info.plist` yourself.

---

## 2. Environment variables

### Secrets — set these in `polkadot-app/env-vars.sh` or the CI environment

| Variable | Used for | If empty |
|----------|----------|----------|
| `SENTRY_DSN` | Sentry crash/issue reporting DSN (`TESTNET_FEATURE` builds only) | Issue monitoring disabled |
| `MELD_BASIC_AUTH_TOKEN` | Meld fiat on-ramp basic auth (`<key>:<secret>`, base64) | Fiat on-ramp auth unset |

### Signing & distribution — GitHub Actions secrets (not needed for local simulator runs)

These are the names the shipped pipeline reads (`.github/workflows/`,
`.github/actions/`). Unlike the table above, they **are** contracts: rename one
and the workflow that reads it fails.

Required for any signed build:

| Secret | Used for | Read by |
|--------|----------|---------|
| `ASC_KEY_ID` | App Store Connect API key ID | TestFlight upload, build-number lookup, device registration, signing refresh |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID | same as above |
| `ASC_KEY_BASE64` | Base64-encoded `.p8` private key | same as above |
| `KEYCHAIN_PASSWORD` | Password for the temporary CI keychain | every signed build |
| `MATCH_PASSWORD` | Passphrase that decrypts the `match` assets | every signed build |
| `FASTLANE_RO_PAT` | Fine-grained PAT with read access to the `match` repo | every signed build |
| `FASTLANE_RW_PAT` | The same PAT with write access | `update_signing_data.yml` only |
| `GOOGLE_SERVICE_INFO_DEV_BASE64` | Base64 development `GoogleService-Info.plist` | PR builds and tests |
| `GOOGLE_SERVICE_INFO_RELEASE_BASE64` | Base64 production `GoogleService-Info.plist` | release and nightly archives, nightly simulator build |
| `GOOGLE_SERVICE_INFO_SAFETY_BASE64` | Base64 Safetynet `GoogleService-Info.plist` (separate Firebase app for `…​.safety`) | Safetynet archives |

Required only by the distribution target you actually use:

| Secret | Used for | Read by |
|--------|----------|---------|
| `CREDENTIAL_FILE_CONTENT` | Google service-account JSON for App Distribution | `firebase_debug_distribution.yml` |
| `FIREBASE_APP_ID` | Firebase App Distribution app ID (`1:…:ios:…`) | `firebase_debug_distribution.yml` |
| `SCW_ACCESS_KEY`, `SCW_SECRET_KEY` | Credentials for the S3 artifact bucket | every workflow that uploads an `.ipa` |
| `SENTRY_AUTH_TOKEN` | Uploading dSYMs to Sentry (the build phase skips when `sentry-cli` is unconfigured — see §9) | signed builds |

Optional — these gate reporting steps only, and a fork can leave them unset:

| Secret | Used for | Read by |
|--------|----------|---------|
| `ALLURE_TOKEN` | Triggering the Allure TestOps run after a build | `_build_distribute.yml`, `testflight_distribution.yml` |
| `NOTIFICATION_BOT_URL`, `NOTIFICATION_BOT_TOKEN` | Build success/failure notifications | `_build_distribute.yml`, `nightly_distribution.yml` |
| `TESTFLIGHT_DISTRIBUTION_LINK`, `WEB_PAGE_DISTRIBUTION_LINK` | One ready-to-render markdown link entry each, e.g. `[TestFlight](https://testflight.apple.com/join/<id>)`. Kept in secrets so access hints stay out of the repo. | `release_distribution.yml`, `nightly_distribution.yml` |
| `TESTFLIGHT_SAFETY_DISTRIBUTION_LINK`, `WEB_PAGE_SAFETY_DISTRIBUTION_LINK` | A TestFlight join link is per-group per-app, and Safetynet is its own app | `nightly_distribution.yml` |

`SENTRY_DSN` and `MELD_BASIC_AUTH_TOKEN` from the first table are also stored as
GitHub Actions secrets, because CI runs `generate_secrets.sh` from
`.github/actions/configure-secrets` instead of reading `env-vars.sh`.

Tester groups are a workflow variable rather than a secret: `FIREBASE_GROUPS` is
set in `firebase_debug_distribution.yml` (default `polkadotapp-ios`) and can be
overridden per run.

Backend and on-chain endpoints (identity backend, IPFS gateway, DotNS resolver,
Web3 Summit, game dashboard) are **not** build-time variables: the app fetches
them at runtime via Firebase Remote Config (see `RemoteAppConfig` and
`FirebaseApplicationService`).

---

## 3. Firebase setup

The app uses Firebase for Remote Config. The real `GoogleService-Info.plist`
files are **not** committed.

1. Create a Firebase project and register two iOS apps — one for development
   (bundle id `…​.develop`) and one for production.
2. Download each `GoogleService-Info.plist` and save them as:
   - `polkadot-app/GoogleService/GoogleService-Info-Dev.plist`
   - `polkadot-app/GoogleService/GoogleService-Info-Release.plist`
   - `polkadot-app/GoogleService/GoogleService-Info-Safety.plist`
3. During a build, the **"Google info"** build phase copies the correct one to
   `polkadot-app/GoogleService-Info.plist` based on `$CONFIGURATION`
   (Debug/Dev/DevCI → Dev, Safetynet → Safety, Release/Nightly → Release). In CI
   (`RUN_IN_CI=true`) this copy is skipped — provide the active plist yourself.

`*.plist.template` files document the expected structure with placeholder values;
`setup-secrets.sh` copies them into the real filenames so a fresh checkout builds
with an inert Firebase configuration until you drop in real plists.

---

## 4. Build configurations

| Configuration | Bundle id | Environment |
|---------------|-----------|-------------|
| `Debug` / `DevCI` | `…​.develop` | Unstable preview backend |
| `Nightly` | production id | Stable testnet, full feature set — TestFlight internal testers |
| `Release` | production id | Mainnet — TestFlight internal testers |
| `Safetynet` | `…​.safety` | Nightly chains, Release feature set — the release build proven before release; separate app, installs alongside production |

Bundle ids, app name, icon and deep-link scheme live in
`Configs/*.xcconfig`, `polkadot-app/Configs/*.xcconfig` and
`NotificationServiceExtension/Configs/*.xcconfig`. Change them to your own
identifiers before distributing.

---

## 5. Code signing

You need an Apple Developer account and a registered App ID for the app **and**
its `NotificationServiceExtension`.

Recommended: **App Store Connect API key** (`.p8`) for non-interactive signing
and uploads. Generate one in App Store Connect → Users and Access → Integrations
→ Keys. The shipped pipeline reads it from the `ASC_KEY_ID`, `ASC_ISSUER_ID`
and `ASC_KEY_BASE64` secrets (§2); if you drive the upload yourself, export it
under whatever names your own tooling expects.

For certificates and provisioning profiles, pick one of:

- **Xcode automatic signing** — simplest for local builds and Xcode Cloud.
- **A shared signing repo** (e.g. Fastlane `match`) — store certs/profiles
  encrypted in a private git repo; each machine/CI runner fetches them. `match`
  works with any private repo you control.
- **Manual** — export a Distribution certificate (`.p12`) and the provisioning
  profiles, import them into the build keychain in CI.

In CI, create a dedicated keychain, import the certificate, and select the right
provisioning profile via the export options when archiving.

---

## 6. Build & archive

```bash
# Generate build-time config (also run automatically by the Xcode build phase)
./Runscripts/generate_secrets.sh

# Archive
xcodebuild -project polkadot-app.xcodeproj \
  -scheme polkadot-app \
  -configuration Release \
  -archivePath build/polkadot-app.xcarchive \
  archive

# Export a signed .ipa (provide an ExportOptions.plist describing the method,
# team id and provisioning profiles)
xcodebuild -exportArchive \
  -archivePath build/polkadot-app.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/
```

A minimal `ExportOptions.plist` for App Store distribution:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>YOUR_TEAM_ID</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
```

Use `method = ad-hoc` (or `development`) for Firebase App Distribution builds.

---

## 7. Distribute to TestFlight

After exporting an App Store `.ipa`, upload it with Apple's notarised tool using
your App Store Connect API key:

```bash
xcrun altool --upload-app -f build/polkadot-app.ipa -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"
```

(`xcrun altool` reads the `.p8` from `~/.appstoreconnect/private_keys/` or
`./private_keys/`. `xcrun notarytool`/`Transporter` are alternatives.)

The build then appears in App Store Connect → TestFlight. Add it to internal or
external tester groups there, or automate group assignment with the App Store
Connect API.

---

## 8. Distribute to Firebase App Distribution

Build an `ad-hoc` signed `.ipa`, then upload with the Firebase CLI:

```bash
firebase appdistribution:distribute build/polkadot-app.ipa \
  --app "$FIREBASE_APP_ID" \
  --groups "$FIREBASE_GROUPS" \
  --release-notes "Your release notes"
```

Authenticate the CLI with a Google service account that has the **Firebase App
Distribution Admin** role (`GOOGLE_APPLICATION_CREDENTIALS` pointing at the
service-account JSON, or `--service-credentials-file`).

---

## 9. Crash symbols (Sentry)

Sentry is disabled for `Release` builds — the SDK is only compiled into
`TESTNET_FEATURE` configurations (`Debug`/`DevCI`/`Nightly`). Accordingly, the
**"Upload Debug Symbols to Sentry"** Xcode build phase uploads dSYMs on all
configurations except `Debug` and `Release`, and only when `sentry-cli` is
installed; otherwise it prints a warning and continues.

> The build phase currently hardcodes `SENTRY_ORG` and `SENTRY_PROJECT` (set to
> the upstream project). **Change these to your own org/project** — or remove
> the build phase entirely — before uploading symbols from your own builds.
> Authenticate `sentry-cli` with a `SENTRY_AUTH_TOKEN` in your environment.

---

## 10. The default CI/CD setup

The repo ships a GitHub Actions pipeline (`.github/workflows/`) driven by Fastlane
lanes (`fastlane/`): PR build and tests, plus TestFlight and Firebase
distribution. Distribution workflows are manual (`workflow_dispatch`) and gated to
named maintainers. The pipeline is preconfigured for the upstream project — a fork
supplies its own GitHub Actions secrets, `match` signing repo, and runners to run
it. The steps above (§5–9) are what the lanes automate.

The secrets the workflows expect are listed in §2 under "Signing & distribution",
grouped by whether they are required for any signed build, required for a
particular distribution target, or optional. A fork also needs to repoint
`fastlane/Matchfile` and `.github/actions/install` at its own `match` repository,
and `fastlane/Appfile` at its own Apple team.

Keep every credential in the GitHub Actions secret store — never commit
`env-vars.sh`, the real `GoogleService-Info` plists, signing certificates, or API
keys.
