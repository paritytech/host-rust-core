import { execFileSync, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * A stand-in for the GitHub release the installer and the in-binary updater
 * download from, so both can be exercised without publishing anything.
 *
 * Shared by `truapi-host-installer.test.mjs` (which installs a stub binary) and
 * `scripts/e2e-cli-update.mjs` (which installs the real packaged one).
 */

/** Binary name inside every release archive. */
export const BINARY = "truapi-host";

/**
 * The prebuilt target for this machine, or `undefined` where none is published.
 * Mirrors the `uname` mapping in `scripts/truapi-host-installer.sh`.
 */
export function detectTarget() {
  if (process.platform === "darwin" && process.arch === "arm64") {
    return "aarch64-apple-darwin";
  }
  if (process.platform === "linux" && process.arch === "x64") {
    return "x86_64-unknown-linux-musl";
  }
  if (process.platform === "linux" && process.arch === "arm64") {
    return "aarch64-unknown-linux-musl";
  }
  return undefined;
}

/** A release archive whose `truapi-host` is an executable stand-in script. */
export function stubArchive(body) {
  const staging = mkdtempSync(join(tmpdir(), "truapi-host-archive-"));
  try {
    const binary = join(staging, BINARY);
    writeFileSync(binary, body);
    chmodSync(binary, 0o755);
    const archive = join(staging, "archive.tar.gz");
    execFileSync("tar", ["-czf", archive, "-C", staging, BINARY]);
    return readFileSync(archive);
  } finally {
    rmSync(staging, { recursive: true, force: true });
  }
}

/** A stub that reports `version`, so a swap is observable by running it. */
export function versionReportingArchive(version) {
  return stubArchive(`#!/bin/sh\necho "${BINARY} ${version}"\n`);
}

/**
 * Serve a release tree shaped like the real one, including the percent-encoded
 * `@parity/truapi@<version>` tag path. Assets are keyed by decoded path, so a
 * missing encoding surfaces as a 404 rather than passing silently.
 */
export async function startReleaseServer() {
  const assets = new Map();
  const server = createServer((request, response) => {
    const asset = assets.get(decodeURIComponent(request.url));
    if (asset === undefined) {
      response.writeHead(404);
      response.end("not found");
      return;
    }
    response.writeHead(200, { "content-length": asset.length });
    response.end(asset);
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));

  return {
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    /**
     * Publish `archive` as `version`, the way release-cli.yml does: the
     * archive and its digest first, the stable pointer last.
     */
    publish(version, target, archive, { corruptChecksum = false } = {}) {
      const name = `${BINARY}-${version}-${target}.tar.gz`;
      const tag = `/releases/download/@parity/truapi@${version}`;
      const digest = corruptChecksum
        ? "0".repeat(64)
        : createHash("sha256").update(archive).digest("hex");
      assets.set(`${tag}/${name}`, archive);
      assets.set(`${tag}/${name}.sha256`, Buffer.from(`${digest}  ${name}\n`));
      this.setPointer(version);
    },
    /** Move the stable pointer without touching any archive. */
    setPointer(version) {
      assets.set(
        "/releases/download/truapi-host-cli-stable/version",
        Buffer.from(`${version}\n`),
      );
    },
    close: () => new Promise((done) => server.close(done)),
  };
}

/**
 * Run a command and collect its result.
 *
 * Everything has to be async: a synchronous spawn would block the event loop
 * the release server runs on, so the download it is serving would never be
 * answered and the call would deadlock.
 */
export function run(command, arguments_, options = {}) {
  return new Promise((done, fail) => {
    const child = spawn(command, arguments_, {
      ...options,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => (stdout += chunk));
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.on("error", fail);
    child.on("close", (status) => done({ status, stdout, stderr }));
    if (options.input !== undefined) child.stdin.write(options.input);
    child.stdin.end();
  });
}

/**
 * Environment that points the installer and the updater at `baseUrl`.
 *
 * CARGO_HOME is sandboxed as well: installing clears a cargo-installed copy, so
 * an inherited CARGO_HOME would let the suite delete a developer's real
 * `truapi-host`.
 */
export function installEnvironment(home, baseUrl) {
  return {
    HOME: home,
    CARGO_HOME: join(home, "cargo"),
    TRUAPI_HOST_RELEASE_BASE_URL: baseUrl,
    TRUAPI_HOST_INSTALL_DIR: join(home, "share"),
    TRUAPI_HOST_BIN_DIR: join(home, "bin"),
    PATH: `${join(home, "bin")}:${process.env.PATH}`,
  };
}
