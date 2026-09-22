#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { stripVTControlCharacters } from "node:util";
import {
  detectTarget,
  installEnvironment,
  run,
  startReleaseServer,
} from "./lib/truapi-host-release.mjs";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const target = process.env.CLI_TARGET || detectTarget();
const version = readFileSync(
  join(repoRoot, "rust/crates/truapi-host-cli/Cargo.toml"),
  "utf8",
).match(/^version = "(.*)"$/m)[1];

const sdkScript = String.raw`import assert from "node:assert/strict";
import { createApp } from "@parity/product-sdk";
import {
  bindHost,
  getAccountsProvider,
  getHostLocalStorage,
  getTruApi,
  subscribeConnectionStatus,
  type HostConnectionStatus,
  type TruApi,
} from "@parity/product-sdk/host";
import type { HostContext } from "./script.types.d.ts";

declare const truapi: TruApi;
declare const host: HostContext;

const unbind = bindHost({
  client: truapi,
  signal: host.signal,
  apiVersion: host.apiVersion,
});
const statuses: HostConnectionStatus[] = [];
const unsubscribe = subscribeConnectionStatus((status) => statuses.push(status));
try {
  assert(process.cwd() === import.meta.dir, "Managed scripts use their project directory");
  assert(process.env.TRUAPI_FRAME_URL?.startsWith("ws+unix:"), "Use the default Unix socket");
  assert(await getTruApi() === truapi, "SDK must borrow the runner's connected client");
  assert.deepEqual(statuses, ["connected"]);

  const accounts = await getAccountsProvider();
  assert(accounts, "SDK account API available");
  const [sdkUser, rawUser] = await Promise.all([
    accounts.getUserId(),
    truapi.account.getUserId(),
  ]);
  assert(sdkUser.isErr() && rawUser.isErr(), "Fresh pairing host has no account");
  assert.deepEqual(sdkUser.error, rawUser.error);

  const connection = await new Promise<unknown>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Account subscription timed out")), 5000);
    const subscription = accounts.subscribeAccountConnectionStatus((status) => {
      clearTimeout(timeout);
      subscription.unsubscribe();
      resolve(status);
    });
    subscription.onInterrupt((reason) => {
      clearTimeout(timeout);
      reject(new Error("Account subscription interrupted", { cause: reason }));
    });
  });
  assert.equal(connection, "Disconnected");

  const storage = await getHostLocalStorage();
  assert(storage, "SDK storage API available");
  await storage.writeString("sdk-e2e", "stored through the shared host");
  assert.equal(await storage.readString("sdk-e2e"), "stored through the shared host");
  const rawStored = await truapi.localStorage.read({ key: "sdk-e2e" });
  assert(rawStored.isOk(), "Raw client reads SDK storage");
  assert.equal(rawStored.value.value, "0x73746f726564207468726f756768207468652073686172656420686f7374");
  await storage.clear("sdk-e2e");

  const app = await createApp({ name: host.productId, cloudStorage: false });
  assert.equal(app.cloudStorage, null);
  await app.localStorage.set("app-e2e", "created in a script");
  assert.equal(await app.localStorage.get("app-e2e"), "created in a script");
  await app.localStorage.remove("app-e2e");
} finally {
  unbind();
  assert.deepEqual(statuses, ["connected", "disconnected"]);
  unsubscribe();
}
assert(!host.signal.aborted, "Unbinding does not close the runner's connection");
assert(await truapi.account.getUserId().then((result) => result.isErr()));
console.log("SDK_E2E_OK");
`;

const ptyRelay = String.raw`
import errno, fcntl, os, pty, select, signal, struct, sys, termios

child, terminal = pty.fork()
if child == 0:
    os.execvpe(sys.argv[1], sys.argv[1:], os.environ)
fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 180, 0, 0))
def stop(signum, frame):
    try:
        os.killpg(child, signal.SIGTERM)
    except ProcessLookupError:
        pass
signal.signal(signal.SIGTERM, stop)
columns = 180
def redraw(signum, frame):
    global columns
    columns = 181 if columns == 180 else 180
    fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack("HHHH", 60, columns, 0, 0))
signal.signal(signal.SIGUSR1, redraw)
readers = [terminal, sys.stdin.fileno()]
while terminal in readers:
    for source in select.select(readers, [], [])[0]:
        try:
            data = os.read(source, 65536)
        except OSError as error:
            if error.errno != errno.EIO:
                raise
            data = b""
        if not data:
            readers.remove(source)
        elif source == terminal:
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
        else:
            os.write(terminal, data)
_, status = os.waitpid(child, 0)
sys.exit(os.waitstatus_to_exitcode(status))
`;

function terminalSession(binary, args, environment, cwd) {
  const child = spawn("python3", ["-u", "-c", ptyRelay, binary, ...args], {
    cwd,
    env: { ...environment, TERM: "xterm-256color" },
    stdio: ["pipe", "pipe", "pipe"],
  });
  let output = "";
  let exitCode;
  const exited = new Promise((resolveExit, rejectExit) => {
    child.on("error", rejectExit);
    child.on("close", (code) => {
      exitCode = code;
      resolveExit(code);
    });
  });
  child.stdout.on("data", (data) => {
    output += data;
    appendFileSync(join(cwd, "terminal.raw.log"), data);
  });
  child.stderr.on("data", (data) => (output += data));
  return {
    get output() {
      return stripVTControlCharacters(output);
    },
    mark: () => output.length,
    send: (command) => child.stdin.write(command),
    async waitFor(expected, start = 0, timeout = 60000, idle = true) {
      const deadline = Date.now() + timeout;
      let nextRedraw = Date.now() + 500;
      while (Date.now() < deadline) {
        if (output.length > 0 && Date.now() >= nextRedraw) {
          // Resizing exposes complete frames instead of Ratatui character deltas.
          child.kill("SIGUSR1");
          nextRedraw = Date.now() + 1000;
        }
        const currentFrame = stripVTControlCharacters(
          output.slice(output.lastIndexOf("\x1b[2J")),
        ).replace(/\s/g, "");
        if (
          stripVTControlCharacters(output.slice(start))
            .replace(/\s/g, "")
            .includes(expected.replace(/\s/g, "")) &&
          (!idle || !currentFrame.includes("Running/script"))
        )
          return;
        assert.equal(
          exitCode,
          undefined,
          `Host exited before ${expected}: ${stripVTControlCharacters(output.slice(-16000))}`,
        );
        await new Promise((done) => setTimeout(done, 50));
      }
      throw new Error(
        `Timed out waiting for ${expected}:\n${stripVTControlCharacters(output.slice(start)).slice(-16000)}`,
      );
    },
    async close() {
      if (exitCode === undefined) child.kill("SIGTERM");
      await exited;
    },
    async waitForExit() {
      let timer;
      try {
        return await Promise.race([
          exited,
          new Promise((_resolve, reject) => {
            timer = setTimeout(
              () => reject(new Error("Host did not exit")),
              10000,
            );
          }),
        ]);
      } finally {
        clearTimeout(timer);
      }
    },
  };
}

async function checkedRun(label, command, args, options) {
  const result = await run(command, args, { timeout: 120000, ...options });
  assert.equal(
    result.status,
    0,
    `${label}:\n${result.stdout}\n${result.stderr}`,
  );
  console.log(`  ok    ${label}`);
  return result;
}

async function main() {
  assert(target, "No packaged CLI target for this platform");
  const archive = resolve(
    process.env.CLI_ARCHIVE ||
      join(repoRoot, `target/dist/truapi-host-${version}-${target}.tar.gz`),
  );
  assert(existsSync(archive), `Missing ${archive}; run make cli-dist`);
  const tarballs = ["SDK_TARBALL", "SDK_HOST_TARBALL"].map((name) => {
    assert(
      process.env[name],
      `Set ${name} to the corresponding packed SDK package`,
    );
    const path = resolve(process.env[name]);
    assert(existsSync(path), `Missing ${name}: ${path}`);
    return `file:${path}`;
  });
  const tools = join(repoRoot, ".agent/tools");
  mkdirSync(tools, { recursive: true });
  const workspace = mkdtempSync(join(tools, "sdk-e2e-"));
  const project = join(workspace, "project with spaces");
  const state = join(workspace, "state");
  const binary = join(workspace, "bin/truapi-host");
  const release = await startReleaseServer();
  release.publish(version, target, readFileSync(archive));
  const environment = {
    ...process.env,
    ...installEnvironment(workspace, release.baseUrl),
    TRUAPI_HOST_NO_UPDATE: "1",
    TRUAPI_SCRIPT_SDK: "0.0.0-script-sdk-e2e-missing",
    BUN_INSTALL_CACHE_DIR: join(workspace, "bun-cache"),
    VISUAL: "true",
    EDITOR: "true",
  };
  delete environment.TRUAPI_HOST_RUNNER;
  delete environment.TRUAPI_SCRIPT_SDK_HOST;
  const args = ["pairing-host", "--base-path", state, "--auto-accept"];
  let terminal;
  try {
    await checkedRun(
      "Install real CLI archive",
      "bash",
      [join(repoRoot, "scripts/truapi-host-installer.sh")],
      {
        env: environment,
        cwd: workspace,
      },
    );
    terminal = terminalSession(binary, args, environment, workspace);
    await terminal.waitFor("Listening for product frames");
    terminal.send(`/script --new ${project}\r`);
    await terminal.waitFor(
      "Project retained; fix the package or network error",
    );
    const scriptPath = join(project, "script.ts");
    const manifestPath = join(project, "package.json");
    const starter = readFileSync(scriptPath, "utf8");
    assert.match(starter, /bindHost/);
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    manifest.dependencies["@parity/product-sdk"] = tarballs[0];
    manifest.overrides = { "@parity/product-sdk-host": tarballs[1] };
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    const retry = terminal.mark();
    terminal.send("/script --edit\r");
    await terminal.waitFor("Script saved", retry, 180000);
    assert.equal(readFileSync(scriptPath, "utf8"), starter);
    writeFileSync(join(project, "second-script.ts"), starter);
    await checkedRun(
      "Two generated starters typecheck against packed SDK",
      "bun",
      ["run", "typecheck"],
      {
        env: environment,
        cwd: project,
      },
    );
    rmSync(join(project, "second-script.ts"));
    const invalidScript = join(project, "invalid-script.ts");
    writeFileSync(
      invalidScript,
      'import { createApp } from "@parity/product-sdk";\nvoid createApp({ name: 42 });\n',
    );
    const invalidTypes = await run("bun", ["run", "typecheck"], {
      env: environment,
      cwd: project,
      timeout: 30000,
    });
    assert.notEqual(
      invalidTypes.status,
      0,
      "SDK arguments must retain their types",
    );
    assert.match(
      invalidTypes.stdout + invalidTypes.stderr,
      /invalid-script\.ts.*TS2322/,
    );
    rmSync(invalidScript);
    assert(existsSync(join(project, "bun.lock")), "Project has a lockfile");
    writeFileSync(
      scriptPath,
      `${starter}\nexport default async function () {\n  assert(await getHostLocalStorage(), "SDK remains bound for the default function");\n  console.log("SDK_DEFAULT_FUNCTION_OK");\n}\n`,
    );
    const starterRun = terminal.mark();
    terminal.send("/script --run\r");
    await terminal.waitFor("saved value", starterRun);
    await terminal.waitFor("SDK_DEFAULT_FUNCTION_OK", starterRun);
    await terminal.waitFor("Script finished", starterRun);
    console.log(
      "  ok    Generated starter and exported default function share the SDK binding",
    );
    writeFileSync(scriptPath, sdkScript);
    await checkedRun(
      "SDK integration script typechecks",
      "bun",
      ["run", "typecheck"],
      {
        env: environment,
        cwd: project,
      },
    );
    const scriptRun = terminal.mark();
    terminal.send("/script --run\r");
    await terminal.waitFor("SDK_E2E_OK", scriptRun);
    await terminal.waitFor("Script finished", scriptRun);
    console.log(
      "  ok    SDK account, subscription, storage, createApp, and shared connection",
    );
    terminal.send("/quit\r");
    assert.equal(await terminal.waitForExit(), 0);
    writeFileSync(join(workspace, "setup.log"), terminal.output);

    const lock = readFileSync(join(project, "bun.lock"), "utf8");
    const offline = {
      ...environment,
      npm_config_registry: "http://127.0.0.1:1",
      BUN_CONFIG_REGISTRY: "http://127.0.0.1:1",
      BUN_INSTALL_CACHE_DIR: join(workspace, "empty-cache"),
      HTTP_PROXY: "http://127.0.0.1:1",
      HTTPS_PROXY: "http://127.0.0.1:1",
    };
    terminal = terminalSession(binary, args, offline, workspace);
    await terminal.waitFor("Listening for product frames");
    terminal.send("/script --edit\r");
    await terminal.waitFor("Script saved");
    assert.equal(readFileSync(scriptPath, "utf8"), sdkScript);
    const rerun = terminal.mark();
    terminal.send("/script --run\r");
    await terminal.waitFor("SDK_E2E_OK", rerun);
    await terminal.waitFor("Script finished", rerun);
    assert.equal(readFileSync(join(project, "bun.lock"), "utf8"), lock);
    assert.doesNotMatch(
      terminal.output.replace(/\s/g, ""),
      /Installingscriptdependencies/,
    );
    console.log(
      "  ok    Remembered project reopens and reruns with registry unavailable",
    );

    writeFileSync(
      scriptPath,
      'console.log("SDK_E2E_WAITING");\nawait new Promise(() => {});\n',
    );
    const waiting = terminal.mark();
    terminal.send("/script --run\r");
    await terminal.waitFor("SDK_E2E_WAITING", waiting, 60000, false);
    terminal.send("\x03");
    await terminal.waitFor("command cancelled", waiting);
    writeFileSync(
      scriptPath,
      sdkScript.replace("SDK_E2E_OK", "SDK_E2E_AFTER_CANCEL_OK"),
    );
    const afterCancel = terminal.mark();
    terminal.send("/script --run\r");
    await terminal.waitFor("SDK_E2E_AFTER_CANCEL_OK", afterCancel);
    await terminal.waitFor("Script finished", afterCancel);
    terminal.send("/quit\r");
    assert.equal(await terminal.waitForExit(), 0);
    writeFileSync(join(workspace, "offline.log"), terminal.output);
    console.log("  ok    Cancellation returns control and permits another run");

    writeFileSync(scriptPath, sdkScript);
    const relativeRunner = await checkedRun(
      "Relative runner override resolves before changing to the project directory",
      binary,
      [...args, "--script", scriptPath],
      {
        env: { ...offline, TRUAPI_HOST_RUNNER: "share/current/runner.js" },
        cwd: workspace,
      },
    );
    assert.match(relativeRunner.stdout + relativeRunner.stderr, /SDK_E2E_OK/);

    writeFileSync(
      scriptPath,
      'throw new Error("SDK_E2E_INTENTIONAL_FAILURE", { cause: new Error("SDK_E2E_UNDERLYING_FAILURE") });\n',
    );
    const failure = await run(binary, [...args, "--script", scriptPath], {
      env: offline,
      cwd: workspace,
      timeout: 30000,
    });
    assert.notEqual(failure.status, 0);
    assert.match(
      failure.stdout + failure.stderr,
      /SDK_E2E_INTENTIONAL_FAILURE/,
    );
    assert.match(failure.stdout + failure.stderr, /script\.ts/);
    writeFileSync(scriptPath, sdkScript);
    console.log(
      "  ok    Script errors preserve nonzero status and source location",
    );
    console.log(`SDK integration passed. Evidence: ${workspace}`);
    rmSync(join(workspace, "bun-cache"), { recursive: true, force: true });
  } finally {
    if (terminal) {
      writeFileSync(join(workspace, "last-terminal.log"), terminal.output);
      await terminal.close();
    }
    await release.close();
    console.log(`Artifacts retained in ${workspace}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
