# Deployment Guide

This document explains **how to build, sign and publish** the Polkadot Android
Community application, and **which environment variables / secrets** you need to
configure.

It is intentionally **generic**. This repository ships GitHub Actions for the
maintained build and distribution flows, while this guide describes the
*building blocks* so that a fork or a community deployment can use its own
credentials.

> **Scope:** this is the manual / reference guide for the workflows under
> `.github/workflows` and for custom deployments.

---

## 1. How publishing works (overview)

A release is just a **signed APK/AAB** of a chosen build variant, delivered through
one or more channels. The app is built with Gradle, has native Rust components
(built via the NDK), and reads all credentials from `local.properties` **or**
environment variables (see §5). The typical flow is:

1. Provision the toolchain (§2).
2. Provide a signing keystore (§3) and a Firebase `google-services.json` (§4) — both editions need it, because Remote Config is required for the app to run.
3. Set the required environment variables / secrets (§5).
4. Build the edition you want to ship (§6).
5. Deliver the artifact through a channel of your choice (§7):
   Google Play, Firebase App Distribution, GitHub Releases, object storage, or a
   direct APK link.

### Distribution editions

The app ships two parallel distribution tracks:

| Edition | Target | Services | Channel |
|---------|--------|----------|---------|
| `gp` | Standard Android / Google Play | Google Mobile Services (GMS), Firebase, Play Integrity | Google Play Store (AAB/APK) |
| `vanilla` | **GrapheneOS** and other GMS-free environments | No Google Play Services; Firebase Remote Config only | Sideloadable APK (GitHub Releases, direct link, etc.) |

The `vanilla` edition is a first-class release track aimed at privacy-focused users
running [GrapheneOS](https://grapheneos.org/). It carries the same core app
functionality and is fully operational without Google Play Services. Google Sign-In,
Firebase Auth, Firebase Analytics, and Firebase Crashlytics are excluded from the
`vanilla` APK.

Both editions do initialize the default `FirebaseApp`, because **Firebase Remote
Config is required for the app to function** (`tools/remoteconfig:impl` drives feature
gates, endpoints, and transaction extension versions). Remote Config does not depend on
Google Play Services being present on the device — it reaches the Firebase REST
endpoints directly and identifies the install through Firebase Installations — so it
works on GrapheneOS. Firebase Messaging and Firebase App Check remain compile-time
transitive dependencies (from `tools/push-notifications:impl` and
`tools/integrity:impl`) but stay inert in `vanilla`: FCM token auto-init is switched
off in `app/src/vanilla/AndroidManifest.xml`, and App Check has no injection sites.

The `vanilla` edition is distributed as a standalone APK alongside, not instead of,
the Google Play version.

---

## 2. Toolchain / prerequisites

These versions are what the project is known to build with (they mirror the
previously-used CI environment):

| Tool            | Version                | Notes                                             |
|-----------------|------------------------|---------------------------------------------------|
| JDK             | 21 (Temurin)           | Required by AGP / Kotlin                           |
| Android SDK     | latest                 | Plus build-tools matching the project             |
| Android NDK     | r29                    | Needed for the native Rust bindings               |
| Clang           | 21                     | Native toolchain                                  |
| Rust            | stable                 | + targets below                                   |
| `cargo-ndk`     | latest                 | `cargo install cargo-ndk`                         |
| Node.js         | 24                     | Build helpers                                     |
| Python          | 3.13                   | Version-management scripts (§6)                   |

Rust targets:

```bash
rustup target add aarch64-linux-android
rustup target add armv7-linux-androideabi
rustup target add x86_64-linux-android
rustup target add i686-linux-android
```

Point Gradle at the NDK by adding to `local.properties`:

```properties
ndk.dir=/path/to/android-ndk-r29
sdk.dir=/path/to/android-sdk
```

See `.github/README.md` for the local developer bootstrap (`developer-tools/setup.sh`).

---

## 3. Signing

The app defines two signing configs in `app/build.gradle.kts`:

- **`dev`** — used by the `debug` and `nightly` build types.
- **`release`** — used by the `release` build type.

### 3.1 Generate a keystore

```bash
keytool -genkeypair -v \
  -keystore release_key.jks \
  -alias my-release-key \
  -keyalg RSA -keysize 2048 -validity 10000
```

### 3.2 Where the keystore file lives

By default the build looks for the files relative to the repo root:

- dev: `develop_key.jks`
- release: `release_key.jks`

You can override the path with `DEV_KEYSTORE_FILE` / `RELEASE_KEYSTORE_FILE`
(see §5). In CI it is common to store the keystore base64-encoded in a secret and
decode it before the build:

```bash
echo "$RELEASE_KEYSTORE_BASE64" | base64 --decode > release_key.jks
```

### 3.3 Passwords / alias

Provided via the signing environment variables in §5
(`*_KEYSTORE_PASS`, `*_KEYSTORE_KEY_ALIAS`, `*_KEYSTORE_KEY_PASS`).

---

## 4. `google-services.json` (Firebase)

> **Required by both editions.** Firebase Remote Config is mandatory for the app to
> run, so `vanilla`/GrapheneOS builds need this file too. Without it the Google
> Services plugin fails the build.

Place `google-services.json` in the `app` module root so that a single file covers
every flavor and build type:

```
app/google-services.json
```

The module root is the plugin's fallback location, so `gpDebug`, `gpNightly`,
`gpRelease` and their `vanilla` counterparts all resolve to it. A flavor-specific
`app/src/gp/google-services.json` still takes precedence for `gp` variants if you
need to point the two editions at different Firebase projects.

`vanilla` needs no separate Firebase app registration: product flavors add no
`applicationIdSuffix` (only build types do), so both editions share the same
application ids and therefore the same `google-services.json` entries.

Obtain it from **your own** Firebase project (Project settings → Your apps →
Android app → download `google-services.json`). In CI decode it into this path
before the build:

```bash
echo "$GOOGLE_SERVICES_JSON_BASE64" | base64 --decode > app/google-services.json
```

---

## 5. Environment variables / secrets reference

All build-time configuration is read by `Properties.readSecretOrDefault(...)` or
`readSecretOrNull(...)` in
`build-logic/convention/src/main/kotlin/Secrets.kt`, with this lookup
order:

1. a key in **`local.properties`**, then
2. an **environment variable** of the same name.

`readSecretOrDefault` supplies a public default, and `readSecretOrNull` returns
`null` for optional configuration.
In GitHub Actions, non-sensitive values from this section can be mapped from GitHub
variables while credentials and mnemonics must be mapped from GitHub secrets.

### 5.1 Signing (required to build a signed variant)

| Variable                   | Used by                   | Required | Description                                  |
|----------------------------|---------------------------|----------|----------------------------------------------|
| `CI_KEYSTORE_PASS`         | `app` dev signingConfig   | yes (dev)| Store password for the dev keystore          |
| `CI_KEYSTORE_KEY_ALIAS`    | `app` dev signingConfig   | yes (dev)| Key alias for the dev keystore               |
| `CI_KEYSTORE_KEY_PASS`     | `app` dev signingConfig   | yes (dev)| Key password for the dev keystore            |
| `RELEASE_KEYSTORE_PASS`    | `app` release signingConfig| yes (rel)| Store password for the release keystore      |
| `RELEASE_KEYSTORE_KEY_ALIAS`| `app` release signingConfig| yes (rel)| Key alias for the release keystore          |
| `RELEASE_KEYSTORE_KEY_PASS`| `app` release signingConfig| yes (rel)| Key password for the release keystore        |
| `DEV_KEYSTORE_FILE`        | `app` dev signingConfig   | no       | Override path to dev keystore (default `../develop_key.jks`) |
| `RELEASE_KEYSTORE_FILE`    | `app` release signingConfig| no      | Override path to release keystore (default `../release_key.jks`) |

> Build types: `debug`/`nightly` use the **dev** config, `release` uses the
> **release** config. Missing passwords default to empty so project configuration
> and unsigned checks can run, but producing a valid signed artifact still requires
> the matching keystore values.

### 5.2 App API keys (consumed by the build via `buildConfigField`)

| Variable           | Used by (module)                           | Required (`gp`) | Required (`vanilla`) | Default | Description                          |
|--------------------|--------------------------------------------|-----------------|----------------------|---------|--------------------------------------|
| `GOOGLE_OAUTH_ID`  | `tools/auth/impl` `gp` source set          | for Google sign-in | no                | empty   | Google OAuth client id (Sign-In)     |
| `GOOGLE_PROJECT_ID`| `tools/integrity/impl` `gp` product flavor | for Play Integrity | no                | `0`     | Google Cloud project id (Play Integrity) |
| `W3S_AUTH_KEY`     | `feature/web3summit/impl`                  | for Web3 Summit | for Web3 Summit      | empty   | Web3 Summit auth keypair seed        |

These values no longer block Gradle configuration when absent. Their integrations
validate or reject the placeholder when actually invoked. Both `GOOGLE_OAUTH_ID`
and `GOOGLE_PROJECT_ID` are scoped to the `gp` product flavor in their respective
modules; `vanilla` builds use no-op/zero values.

#### 5.2.1 App endpoints / values (optional — placeholder defaults)

These are read with the **non-throwing** configuration helpers and fall back to a
harmless placeholder when unset, so the build still succeeds without them. Depending
on the consumer, they become an application ID, manifest placeholder, or BuildConfig
field. Set them in `local.properties` / CI to point at your own infrastructure.

| Variable                    | Used by (module)              | Required | Default (placeholder)          | Description                                                                 |
|-----------------------------|-------------------------------|----------|--------------------------------|-----------------------------------------------------------------------------|
| `APPLICATION_ID`            | `app`                         | no       | `io.paritytech.polkadotapp`    | Installed application ID; changing it creates a different app identity      |
| `APPLICATION_NAME`          | `app`                         | no       | `Polkadot`                     | Base/release launcher name                                                   |
| `DEBUG_APPLICATION_NAME`    | `app` debug build             | no       | `[Debug] <APPLICATION_NAME>`   | Debug launcher name                                                          |
| `NIGHTLY_APPLICATION_NAME`  | `app` nightly build           | no       | `<APPLICATION_NAME>`           | Nightly launcher name                                                        |
| `PRIVACY_POLICY_URL`        | `app`                         | no       | `https://example.com/privacy`  | Privacy-policy destination                                                   |
| `TERMS_OF_USE_URL`          | `app`                         | no       | `https://example.com/terms`    | Terms-of-use destination                                                     |
| `REFERRAL_WEB_HOST`         | `feature/become-citizen/impl` | no       | `referral.example.com`         | Host of the web app that backs referral (`https`) deeplinks                 |
| `GAME_RESULTS_FALLBACK_URL` | `feature/videogame/impl`      | no       | `https://example.com/`         | Last-resort URL for the game-results webview (after DotNs + Remote Config)   |
| `FIRESTORE_DATABASE_ID`     | `tools/backup/impl`            | no       | `(default)`                    | Firestore database used for backup encryption-key records                    |
| `NIGHTLY_FUNDING_MNEMONIC`  | `feature/transactions/impl`   | for funding | empty                       | Mnemonic of the funding account used to top up accounts on nightly/production test contours |
| `LOG_COLLECTION_EMAIL`      | `app`                         | no       | `logs@example.com`             | Recipient address for the in-app "collect logs" debug share action          |
| `CURRENCY_SYMBOL`           | `common`                      | no       | `CASH`                         | Symbol of the in-app digital currency rendered in the UI                     |

> `NIGHTLY_FUNDING_MNEMONIC` controls a funding account — keep it in a secret store
> or untracked `local.properties`, never commit it. When it is empty, requesting the
> nightly/production test funding origin fails explicitly instead of silently using
> a public mnemonic. The separate testnet Alice origin continues to use the public,
> well-known Substrate development fixture.
>
> The value is compiled into `BuildConfig` and can therefore be recovered from a
> distributed APK. GitHub Secrets protect it at rest and mask it in CI logs, but do
> not make it confidential after compilation. Use only a tightly funded disposable
> test account, never a treasury or other valuable mnemonic.

### 5.3 Sentry (crash/error reporting)

| Variable             | Used by               | Required | Description                                            |
|----------------------|-----------------------|----------|--------------------------------------------------------|
| `SENTRY_ORG`         | `app/build.gradle.kts`| no       | Sentry org slug. Default: `your-sentry-org` (placeholder — set to your org) |
| `SENTRY_PROJECT`     | `app/build.gradle.kts`| no       | Sentry project slug. Default: `your-sentry-project` (placeholder — set to your project) |
| `SENTRY_AUTH_TOKEN`  | Sentry Gradle plugin  | no       | Token for source upload. Only used for `debug`/`nightly` (release variant is ignored). Omit to skip upload. |
| `SENTRY_DSN`         | `app` debug/nightly manifests (`${sentryDsn}` manifest placeholder) | no | DSN crashes/errors are reported to. Default: empty (Sentry reporting disabled). Only the `debug`/`nightly` manifests reference it; `release` has no DSN meta-data. |

Override `SENTRY_ORG` / `SENTRY_PROJECT` to point crash reporting at **your** Sentry,
and set `SENTRY_DSN` to the project's DSN (otherwise crash reporting stays disabled).

### 5.4 Build

| Variable      | Used by                                   | Required | Description                                   |
|---------------|-------------------------------------------|----------|-----------------------------------------------|
| `CI_BUILD_ID` | `build-logic/convention/src/main/kotlin/Versions.kt` (`versionCode`)| no | Integer `versionCode`. Defaults to `28` if unset. |

The marketing `versionName` is stored in `build-logic/convention/src/main/kotlin/Versions.kt`
(`DefaultVersionName`) and managed by the scripts in §6.

### 5.5 Legacy / not currently consumed by the build

The previous CI fetched the following secrets, but **no source or build file in this
repository currently reads them**. They are listed for completeness; treat them as
optional and only wire them up if you re-introduce the corresponding integration:

`RAISE_CLIENT_ID_DEBUG`, `RAISE_SECRET_DEBUG`, `RAISE_CLIENT_ID_PROD`,
`RAISE_SECRET_PROD`, `MERCURYO_PRODUCTION_SECRET`, `POSTHOG_HOST`,
`POSTHOG_API_KEY`, `POSTHOG_API_KEY_DEV`, `POSTHOG_API_KEY_PROD`.

### 5.6 Publishing/infra secrets (channel-dependent — see §7)

These are **not** consumed by the Gradle build; you only need them in the publishing
step of whatever channel you choose:

| Variable                          | Channel                       | Description                                |
|-----------------------------------|-------------------------------|--------------------------------------------|
| `FIREBASE_GOOGLE_SERVICE_ACCOUNT` | Firebase App Distribution     | Service-account JSON (content)             |
| Firebase **App ID**               | Firebase App Distribution     | Target Firebase app id                     |
| Play service-account JSON         | Google Play                   | For Play Developer API uploads             |
| `GITHUB_TOKEN`                    | GitHub Releases               | Provided automatically in GitHub Actions   |

---

## 6. Building

Distribution editions: `gp` (Google services — Google Play) and `vanilla` (no GMS —
GrapheneOS / sideload). Build types: `debug`, `nightly`, `release`.

### 6.1 `gp` edition (Google Play)

Standard builds for devices with Google Play Services. Requires `google-services.json`
at `app/src/gp/google-services.json` (§4) and all secrets in §5.

```bash
# Debug (dev signing)
./gradlew assembleGpDebug

# Nightly (dev signing)
./gradlew assembleGpNightly

# Release (release signing) — requires the release keystore + secrets
./gradlew assembleGpRelease
```

Outputs land in `app/build/outputs/apk/gp/<buildType>/`.

### 6.2 `vanilla` edition (GrapheneOS / GMS-free)

The `vanilla` edition produces an APK with **no Google Play Services dependency**: no
Play Integrity, no GMS-backed Sign-In, no Analytics or Crashlytics. It is designed to
run correctly on [GrapheneOS](https://grapheneos.org/) and any other Android
distribution that does not ship Google Play Services. Firebase Remote Config is the
one Firebase service it keeps, because the app cannot function without it; it needs no
Play Services on the device.

Prerequisites that differ from the `gp` edition:

- **`google-services.json` still required** — see §4; Remote Config needs it.
- **`GOOGLE_OAUTH_ID` not required** — `tools/auth/impl` uses a no-op implementation for `vanilla`.
- **`GOOGLE_PROJECT_ID` not required** — scoped to the `gp` flavor in `tools/integrity/impl`.
- All other secrets (signing, `W3S_AUTH_KEY`, Sentry, optional endpoint variables) apply identically.

```bash
# Debug (dev signing)
./gradlew assembleVanillaDebug

# Nightly (dev signing)
./gradlew assembleVanillaNightly

# Release (release signing) — requires the release keystore + secrets
./gradlew assembleVanillaRelease
```

Outputs land in `app/build/outputs/apk/vanilla/<buildType>/`.

The release APK (`app-vanilla-release.apk`) is the artifact distributed to
GrapheneOS users (see §7 → *GrapheneOS / direct APK sideload*).

### Version management

The marketing version and the build number are defined in
`build-logic/convention/src/main/kotlin/Versions.kt`:

```kotlin
private const val DefaultVersionName = "1.0.0"   // versionName
private const val DefaultVersionCode = 28        // versionCode (fallback)
```

- **versionName** — edit `DefaultVersionName` directly when cutting a release.
- **versionCode** — edit `DefaultVersionCode`, or override per build (without editing
  the file) via the `CI_BUILD_ID` environment variable (see §5.4), which takes
  precedence when set.

---

## 7. Publishing channels (pick what you need)

The repository no longer contains these pipelines. Below is **how** each channel is
typically wired so you can implement it on your own infrastructure.

### Google Play

- Upload `app-gp-release.aab`/`.apk` to the Play Console manually, **or**
- Use the Play Developer API (e.g. the `r0adkll/upload-google-play` GitHub Action or
  `fastlane supply`) with a Play service-account JSON.

### Firebase App Distribution (internal/QA builds)

- Upload the signed APK with a Firebase service account
  (`FIREBASE_GOOGLE_SERVICE_ACCOUNT`) and the target **App ID**, e.g. via the
  Firebase CLI (`firebase appdistribution:distribute`) or an equivalent GitHub Action.

### GitHub Releases

Build both editions first, then create a single release attaching both APKs:

```bash
gh release create "v$VERSION" \
  --title "$VERSION" \
  --notes "release notes" \
  app/build/outputs/apk/gp/release/app-gp-release.apk \
  app/build/outputs/apk/vanilla/release/app-vanilla-release.apk
```

`gh` uses the automatically-provided `GITHUB_TOKEN` in Actions. Users on Google Play
receive the `gp` APK through the store; GrapheneOS users download and sideload
`app-vanilla-release.apk` directly (via the Files app, `adb install`, or the
[GrapheneOS App Store](https://github.com/GrapheneOS/Apps) as a longer-term channel).

### Object storage / direct APK

- Upload the APK to any bucket/CDN (S3-compatible, GCS, etc.) and publish the link.

---

## 8. GitHub Actions

The workflows under `.github/workflows` use the configuration described above.
For a fork or another deployment, store non-sensitive branding and endpoint
configuration as **GitHub Actions variables**, and credentials, signing material,
and mnemonics as **GitHub Actions secrets**. Expose both as environment variables;
the Gradle build already reads them via `readSecretOrDefault` and
`readSecretOrNull`, so no code changes are needed. A minimal sketch:

The nightly release notification also reads two workflow-only repository variables:

| Variable | Description |
|----------|-------------|
| `CI_MATRIX_ROOM_IDS` | Comma-separated Matrix room IDs that receive the notification. |
| `NIGHTLY_DOWNLOAD_LINKS` | Multiline Markdown list passed to the notification action as its download links. |

```yaml
name: Build
on: [pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      APPLICATION_ID: ${{ vars.APPLICATION_ID }}
      APPLICATION_NAME: ${{ vars.APPLICATION_NAME }}
      DEBUG_APPLICATION_NAME: ${{ vars.DEBUG_APPLICATION_NAME }}
      NIGHTLY_APPLICATION_NAME: ${{ vars.NIGHTLY_APPLICATION_NAME }}
      PRIVACY_POLICY_URL: ${{ vars.PRIVACY_POLICY_URL }}
      TERMS_OF_USE_URL: ${{ vars.TERMS_OF_USE_URL }}
      LOG_COLLECTION_EMAIL: ${{ vars.LOG_COLLECTION_EMAIL }}
      REFERRAL_WEB_HOST: ${{ vars.REFERRAL_WEB_HOST }}
      GAME_RESULTS_FALLBACK_URL: ${{ vars.GAME_RESULTS_FALLBACK_URL }}
      SENTRY_ORG: ${{ vars.SENTRY_ORG }}
      SENTRY_PROJECT: ${{ vars.SENTRY_PROJECT }}
      SENTRY_DSN: ${{ vars.SENTRY_DSN }}
      FIRESTORE_DATABASE_ID: ${{ vars.FIRESTORE_DATABASE_ID }}
      GOOGLE_OAUTH_ID: ${{ vars.GOOGLE_OAUTH_ID }}
      GOOGLE_PROJECT_ID: ${{ vars.GOOGLE_PROJECT_ID }}
      CI_KEYSTORE_PASS: ${{ secrets.CI_KEYSTORE_PASS }}
      CI_KEYSTORE_KEY_ALIAS: ${{ secrets.CI_KEYSTORE_KEY_ALIAS }}
      CI_KEYSTORE_KEY_PASS: ${{ secrets.CI_KEYSTORE_KEY_PASS }}
      INTERCOM_API_KEY: ${{ secrets.INTERCOM_API_KEY }}
      INTERCOM_APP_ID: ${{ secrets.INTERCOM_APP_ID }}
      W3S_AUTH_KEY: ${{ secrets.W3S_AUTH_KEY }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "21" }
      # ... install Android SDK, NDK r29, Rust + targets, Clang, Node, Python (see §2)
      - run: |
          echo "${{ secrets.DEV_KEYSTORE_BASE64 }}" | base64 --decode > develop_key.jks
          # both editions — Remote Config requires google-services.json
          echo "${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}" | base64 --decode > app/google-services.json
      - name: Build
        env:
          NIGHTLY_FUNDING_MNEMONIC: ${{ secrets.NIGHTLY_FUNDING_MNEMONIC }}
        run: ./gradlew assembleGpDebug --no-daemon --stacktrace
      # To build the vanilla edition instead, omit GOOGLE_OAUTH_ID and
      # GOOGLE_PROJECT_ID (GOOGLE_SERVICES_JSON_BASE64 is still needed), then run:
      # - run: ./gradlew assembleVanillaDebug --no-daemon --stacktrace
```

Add a publishing job (§7) only on the events/branches you want to ship from.
