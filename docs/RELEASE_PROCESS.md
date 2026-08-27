# Release process

The `@parity/truapi` and `@parity/truapi-host` npm packages are published by
[`paritytech/npm_publish_automation`](https://github.com/paritytech/npm_publish_automation).
We never run `npm publish` locally or from a personal account; the
`Release` workflow in `.github/workflows/release.yml` packs the packages
and dispatches the automation.

Releases happen via a dedicated **release PR**. Nothing publishes
automatically on a normal feature merge — only PRs whose title (and
therefore squashed commit subject) starts with `release:` trigger a
publish, and only when they bump the package version.

## How to release

### 1. Cut the protocol version

Run `scripts/cut-version.sh` to crystallize wire types, take an explorer
snapshot, and generate the root `CHANGELOG.md`:

```bash
scripts/cut-version.sh            # crystallize next/, snapshot, changelog
scripts/cut-version.sh --dry-run  # preview without making changes
```

### 2. Bump the package version

```bash
npm run changeset            # interactive: pick patch / minor / major + a short summary
npm run version-packages     # consumes the changeset, bumps package.json + writes CHANGELOG.md
```

The first command writes a markdown file under `.changeset/`; the second
consumes it, bumps the selected package `package.json`, appends the package
`CHANGELOG.md`, deletes the changeset file, and then runs
`scripts/sync-release-versions.mjs`. That script keeps
`rust/crates/truapi/Cargo.toml` and the host package's `@parity/truapi`
dependency aligned with `js/packages/truapi/package.json`; the command then
refreshes `package-lock.json`. A protocol release should therefore include the
`@parity/truapi` package, its changelog, the Cargo version, the host dependency,
and the lockfile. A host-runtime-only release can bump
`@parity/truapi-host` without changing the Rust crate version.

### 3. Open a release PR

Commit the resulting diff and open a PR using the **release** template:

```
https://github.com/paritytech/host-rust-core/compare/main...<your-branch>?template=release.md
```

The PR title must start with `release:`. Convention:

```
release: @parity/truapi 0.1.1
release: @parity/truapi-host 0.1.1
release: @parity/truapi 0.5.0, @parity/truapi-host 0.2.0
release: @parity/android-host 0.1.0
release: @parity/truapi 0.5.0, @parity/ios-host 0.5.0, @parity/android-host 0.1.0
```

Separate multiple package/version targets with commas. The workflow validates
each declared version against its package manifest and publishes every target
whose version is not already on npm in the same automation run.

### 4. Get the PR reviewed and merged

Merge via squash merge (the repo's default). The squash commit subject
defaults to the PR title, so the `release:` prefix carries over to
`main`. **Don't rewrite the squash subject in GitHub's merge dialog** —
the workflow checks the commit subject, and dropping the `release:`
prefix will silently skip the publish. If that does happen, open a
follow-up `release:` PR with any trivial change (a CHANGELOG note tweak,
say); the tag-already-exists guard makes re-runs safe.

### 5. Watch the publish

On merge, CI runs as usual. When CI passes, the `Release` workflow:

1. Confirms the commit subject starts with `release:`.
2. Reads each package/version target from the comma-separated release subject
   and validates it against the corresponding package manifest.
3. Asks npm whether each `<package>@<version>` already exists. Versions the
   registry already serves are skipped, so re-runs are idempotent.
4. Builds generated sources and the host WASM bundle, packs the tarballs, and
   dispatches to `npm_publish_automation`.
5. Polls the registry until every version being released is installable, for up
   to ten minutes.
6. Creates and pushes tags and publishes GitHub Releases, for the confirmed
   versions only.

The dispatch in step 4 returns as soon as GitHub accepts it, which is why step 5
exists: the registry is the only proof a version landed. A green `Release` run
therefore means both packages are installable, not merely that the publish was
requested.

You can still watch the dispatched run under
[`paritytech/npm_publish_automation` Actions](https://github.com/paritytech/npm_publish_automation/actions),
which is where a publish failure reports its reason.

### The native artifacts

The npm packages are not the only release targets. `@parity/ios-host` and
`@parity/android-host` name artifacts that live outside npm, and each is
published by its own job once the release job succeeds.

`@parity/android-host <version>` publishes the Android host AAR as
`io.parity:truapi-host-android:<version>` to GitHub Packages. The job
cross-compiles `libtruapi_server.so` for arm64-v8a, armeabi-v7a and x86_64,
regenerates the UniFFI Kotlin bindings from the same source, and publishes the
AAR with the native libraries inside it, so consumers need only Gradle. Nothing
in the tree records the Android version, so there is no manifest to bump: the
release subject is the only place it appears. See
[`android/truapi-host/README.md`](../android/truapi-host/README.md) for the
consumer setup and the credentials a consumer needs.

Both native jobs are also reachable by a manual `workflow_dispatch` run with a
version input, as an escape hatch. Neither has a tag trigger, because a tag push
cannot use the `workflow_run` gate on green CI and would be an unverified path to
a registry.

## Safety properties

- A feature PR that accidentally bumps `package.json` will **not**
  trigger a publish — only `release:` PRs do.
- A `release:` PR that forgets to bump package versions will be skipped at the
  version-already-on-npm check, not silently re-publish over an existing
  version. That check queries the registry, not the git tags.
- A publish that never reaches npm fails the release, so no tag or GitHub
  Release is created for a version nobody can install. If one package lands and
  another does not, only the one that landed is tagged and the run still fails.
  Re-run it once the publish is fixed; the tag and version checks make that
  safe.
- A release is one unit. The iOS and Android jobs run only after the release job
  succeeds, so a release naming both npm packages and `@parity/ios-host` or
  `@parity/android-host` publishes no XCFramework and no AAR while npm is
  unconfirmed. Re-running covers both. A native-only release is unaffected, since
  it has no npm package to confirm.
- A release that does not name `@parity/android-host` publishes no AAR. The
  Android artifact is opt-in per release, like the iOS one, so a playground-only
  npm bump does not cut an Android version.
- The Android job has no equivalent of the npm "is this version already
  published?" pre-flight check, so re-running a release re-attempts the publish
  and relies on the registry to refuse a duplicate coordinate. Prefer bumping the
  version over re-running a release whose Android publish already succeeded.
- A `release:` PR with mismatched `js/packages/truapi/package.json` and
  `rust/crates/truapi/Cargo.toml` versions is blocked at PR time by the
  `Release version check` workflow.
- The whole flow uses the default `GITHUB_TOKEN`. No GitHub App, no bot
  identity, no separate secrets to manage other than the org-level
  `NPM_PUBLISH_AUTOMATION_TOKEN` that the automation itself relies on.
