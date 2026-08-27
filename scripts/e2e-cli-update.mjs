#!/usr/bin/env node
/**
 * End-to-end check of the truapi-host install and self-update chain.
 *
 * Serves a fake release over HTTP, installs the real packaged binary with the
 * real installer, then drives that binary through `truapi-host update`.
 * Nothing here contacts GitHub.
 *
 *   make cli-dist          # produce the archive this consumes
 *   make e2e-cli-update
 */
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  readlinkSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  detectTarget,
  installEnvironment,
  run,
  startReleaseServer,
  stubArchive,
  versionReportingArchive,
} from "./lib/truapi-host-release.mjs";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const installer = join(repoRoot, "scripts/truapi-host-installer.sh");
const target = process.env.CLI_TARGET || detectTarget();
const version = readFileSync(
  join(repoRoot, "rust/crates/truapi-host-cli/Cargo.toml"),
  "utf8",
).match(/^version = "(.*)"$/m)[1];
const nextVersion = `${version}-next`;

const failures = [];

function check(label, actual, expected) {
  if (Object.is(actual, expected)) {
    console.log(`  ok    ${label}`);
    return;
  }
  failures.push(label);
  console.log(`  FAIL  ${label}`);
  console.log(`          expected: ${JSON.stringify(expected)}`);
  console.log(`          actual:   ${JSON.stringify(actual)}`);
}

async function main() {
  if (target === undefined) {
    console.error("no prebuilt target for this platform");
    return 2;
  }
  const packaged = join(
    repoRoot,
    `target/dist/truapi-host-${version}-${target}.tar.gz`,
  );
  if (!existsSync(packaged)) {
    console.error(`missing ${packaged}`);
    console.error(`run: make cli-dist CLI_TARGET=${target}`);
    return 2;
  }

  const release = await startReleaseServer();
  release.publish(version, target, readFileSync(packaged));

  const home = mkdtempSync(join(tmpdir(), "truapi-host-e2e-"));
  const root = join(home, "share");
  const entrypoint = join(home, "bin/truapi-host");
  const environment = {
    ...process.env,
    ...installEnvironment(home, release.baseUrl),
  };

  try {
    console.log("1. install the packaged binary through the real installer");
    const installed = await run("bash", [installer], { env: environment });
    check("installer exits cleanly", installed.status, 0);
    if (installed.status !== 0) {
      console.error(installed.stderr);
      return 1;
    }
    check(
      "current points at the installed version",
      readlinkSync(join(root, "current")),
      `versions/${version}`,
    );
    check(
      "the PATH entry resolves through current",
      readlinkSync(entrypoint),
      join(root, "current/truapi-host"),
    );
    check(
      "the installed binary reports its version",
      (
        await run(entrypoint, ["--version"], { env: environment })
      ).stdout.trim(),
      `truapi-host ${version}`,
    );

    console.log("2. a managed install with nothing newer published");
    check(
      "update reports up to date",
      (await run(entrypoint, ["update"], { env: environment })).stdout.trim(),
      `truapi-host ${version} is up to date.`,
    );

    console.log("3. a tampered archive is refused");
    release.publish("9.9.9", target, stubArchive("#!/bin/sh\necho pwned\n"), {
      corruptChecksum: true,
    });
    const tampered = await run(entrypoint, ["update"], { env: environment });
    check("update fails closed", tampered.status !== 0, true);
    check(
      "the failure names the checksum",
      /checksum/.test(tampered.stderr),
      true,
    );
    check(
      "the active version is unchanged",
      readlinkSync(join(root, "current")),
      `versions/${version}`,
    );

    console.log("4. updates can be turned off");
    check(
      "TRUAPI_HOST_NO_UPDATE is honoured",
      (
        await run(entrypoint, ["update"], {
          env: { ...environment, TRUAPI_HOST_NO_UPDATE: "1" },
        })
      ).stdout.trim(),
      "Updates are disabled by TRUAPI_HOST_NO_UPDATE.",
    );

    console.log("5. publish a newer version and self-update into it");
    // A stand-in script rather than a second release build, so the content
    // swap is observable. It replaces the real CLI, so nothing after this
    // step can exercise the updater again.
    release.publish(nextVersion, target, versionReportingArchive(nextVersion));
    const linkBefore = readlinkSync(entrypoint);
    const updated = await run(entrypoint, ["update"], { env: environment });
    check(
      "update reports the install",
      updated.stdout.trim(),
      `Installed truapi-host ${nextVersion}; restart to use it.`,
    );
    check(
      "current moved to the new version",
      readlinkSync(join(root, "current")),
      `versions/${nextVersion}`,
    );
    check("the PATH entry is untouched", readlinkSync(entrypoint), linkBefore);
    check(
      "the next run executes the new version",
      (await run(entrypoint, [], { env: environment })).stdout.trim(),
      `truapi-host ${nextVersion}`,
    );
    check(
      "the version it was updated from is still on disk",
      existsSync(join(root, `versions/${version}/truapi-host`)),
      true,
    );

    console.log("6. an unmanaged binary refuses to update itself");
    const sourceBuild = join(repoRoot, `target/${target}/release/truapi-host`);
    const unmanaged = await run(sourceBuild, ["update"], { env: environment });
    check("unmanaged update fails", unmanaged.status !== 0, true);
    check(
      "the failure explains why",
      unmanaged.stderr.includes("was not installed by the installer"),
      true,
    );
    check(
      "the managed install was left alone",
      readlinkSync(join(root, "current")),
      `versions/${nextVersion}`,
    );
  } finally {
    await release.close();
    rmSync(home, { recursive: true, force: true });
  }

  console.log();
  if (failures.length > 0) {
    console.log(`${failures.length} check(s) failed: ${failures.join(", ")}`);
    return 1;
  }
  console.log("all checks passed");
  return 0;
}

process.exit(await main());
