import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const installerPath = join(repoRoot, "scripts/truapi-host-installer.sh");
const installerSource = readFileSync(installerPath);

/**
 * The triple the installer must derive on this machine. A wrong derivation
 * asks the fake release server for an asset it does not serve, so these tests
 * pin the uname mapping as well as the install layout.
 */
const target = detectTarget();

function detectTarget() {
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

/** A tar.gz holding one executable `truapi-host` that echoes its version. */
function buildArchive(version) {
  const staging = mkdtempSync(join(tmpdir(), "truapi-host-archive-"));
  try {
    const binary = join(staging, "truapi-host");
    writeFileSync(binary, `#!/bin/sh\necho "truapi-host ${version}"\n`);
    chmodSync(binary, 0o755);
    const archive = join(staging, "archive.tar.gz");
    execFileSync("tar", ["-czf", archive, "-C", staging, "truapi-host"]);
    return readFileSync(archive);
  } finally {
    rmSync(staging, { recursive: true, force: true });
  }
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

/**
 * Serve a release tree shaped like the real one, including the percent-encoded
 * `@parity/truapi@<version>` tag path. Assets are keyed by decoded path so a
 * missing encoding shows up as a 404 rather than passing silently.
 */
async function startReleaseServer() {
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
    /** Publish `version` for `target`, optionally with a corrupted digest. */
    publish(version, { corruptChecksum = false } = {}) {
      const archive = buildArchive(version);
      const name = `truapi-host-${version}-${target}.tar.gz`;
      const tag = `/releases/download/@parity/truapi@${version}`;
      const digest = corruptChecksum ? "0".repeat(64) : sha256(archive);
      assets.set(`${tag}/${name}`, archive);
      assets.set(`${tag}/${name}.sha256`, Buffer.from(`${digest}  ${name}\n`));
      assets.set(
        "/releases/download/truapi-host-cli-stable/version",
        Buffer.from(`${version}\n`),
      );
    },
    close: () => new Promise((done) => server.close(done)),
  };
}

/**
 * Run a command and collect its result. Everything here has to be async: a
 * synchronous spawn would block the event loop the fake release server runs
 * on, and the installer's own download would then never be answered.
 */
function run(command, arguments_, options = {}) {
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

/** Run the installer the way the documented one-liner does: piped into bash. */
function runInstaller(environment) {
  return run("bash", ["-s"], {
    input: installerSource,
    env: { ...process.env, ...environment },
  });
}

function installEnvironment(home, baseUrl) {
  return {
    HOME: home,
    TRUAPI_HOST_RELEASE_BASE_URL: baseUrl,
    TRUAPI_HOST_INSTALL_DIR: join(home, "share"),
    TRUAPI_HOST_BIN_DIR: join(home, "bin"),
    PATH: `${join(home, "bin")}:${process.env.PATH}`,
  };
}

async function withHome(body) {
  const home = mkdtempSync(join(tmpdir(), "truapi-host-home-"));
  try {
    await body(home);
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
}

test(
  "installs the advertised version and wires the symlink chain",
  {
    skip: target === undefined && "no prebuilt target for this platform",
  },
  async () => {
    const release = await startReleaseServer();
    release.publish("0.10.0");
    try {
      await withHome(async (home) => {
        const result = await runInstaller(
          installEnvironment(home, release.baseUrl),
        );
        assert.equal(result.status, 0, result.stderr);

        const root = join(home, "share");
        const installed = join(root, "versions/0.10.0/truapi-host");
        assert.ok(existsSync(installed), "versioned binary is installed");
        assert.equal(readlinkSync(join(root, "current")), "versions/0.10.0");
        assert.equal(
          realpathSync(join(home, "bin/truapi-host")),
          realpathSync(installed),
        );

        // The PATH entry must reach the binary through `current`, so that an
        // update can swap versions without rewriting the user's symlink.
        assert.equal(
          readlinkSync(join(home, "bin/truapi-host")),
          join(root, "current/truapi-host"),
        );

        const executed = await run(join(home, "bin/truapi-host"), []);
        assert.equal(executed.stdout.trim(), "truapi-host 0.10.0");
      });
    } finally {
      await release.close();
    }
  },
);

test(
  "refuses an archive whose digest does not match",
  {
    skip: target === undefined && "no prebuilt target for this platform",
  },
  async () => {
    const release = await startReleaseServer();
    release.publish("0.10.0", { corruptChecksum: true });
    try {
      await withHome(async (home) => {
        const result = await runInstaller(
          installEnvironment(home, release.baseUrl),
        );
        assert.notEqual(result.status, 0, "installer must fail closed");
        assert.match(result.stderr, /checksum/i);
        assert.ok(
          !existsSync(join(home, "bin/truapi-host")),
          "nothing is installed when verification fails",
        );
      });
    } finally {
      await release.close();
    }
  },
);

test(
  "an upgrade repoints current and leaves the PATH symlink alone",
  {
    skip: target === undefined && "no prebuilt target for this platform",
  },
  async () => {
    const release = await startReleaseServer();
    release.publish("0.10.0");
    try {
      await withHome(async (home) => {
        const environment = installEnvironment(home, release.baseUrl);
        assert.equal((await runInstaller(environment)).status, 0);
        const link = join(home, "bin/truapi-host");
        const linkTarget = readlinkSync(link);

        release.publish("0.10.1");
        const upgrade = await runInstaller(environment);
        assert.equal(upgrade.status, 0, upgrade.stderr);

        const root = join(home, "share");
        assert.equal(readlinkSync(join(root, "current")), "versions/0.10.1");
        assert.equal(readlinkSync(link), linkTarget, "PATH symlink is stable");
        assert.equal((await run(link, [])).stdout.trim(), "truapi-host 0.10.1");
      });
    } finally {
      await release.close();
    }
  },
);

test(
  "TRUAPI_HOST_VERSION pins the install and skips the stable pointer",
  {
    skip: target === undefined && "no prebuilt target for this platform",
  },
  async () => {
    const release = await startReleaseServer();
    release.publish("0.10.1");
    release.publish("0.10.0");
    // Leave the pointer on 0.10.0 while asking for 0.10.1: a pinned install must
    // not consult it at all.
    try {
      await withHome(async (home) => {
        const result = await runInstaller({
          ...installEnvironment(home, release.baseUrl),
          TRUAPI_HOST_VERSION: "0.10.1",
        });
        assert.equal(result.status, 0, result.stderr);
        assert.equal(
          readlinkSync(join(home, "share/current")),
          "versions/0.10.1",
        );
      });
    } finally {
      await release.close();
    }
  },
);

test("reports an unsupported platform instead of installing something wrong", async () => {
  await withHome(async (home) => {
    const fakeBin = join(home, "fake");
    mkdirSync(fakeBin, { recursive: true });
    const uname = join(fakeBin, "uname");
    writeFileSync(
      uname,
      '#!/bin/sh\ncase "$1" in -s) echo Plan9;; *) echo pdp11;; esac\n',
    );
    chmodSync(uname, 0o755);

    const result = await runInstaller({
      HOME: home,
      TRUAPI_HOST_INSTALL_DIR: join(home, "share"),
      TRUAPI_HOST_BIN_DIR: join(home, "bin"),
      PATH: `${fakeBin}:${process.env.PATH}`,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Plan9 pdp11/);
  });
});
