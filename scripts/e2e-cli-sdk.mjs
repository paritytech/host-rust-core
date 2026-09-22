#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import {
  appendFileSync,
  cpSync,
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
import { getAccountsProvider, getHostLocalStorage } from "@parity/product-sdk/host";
import type { TrUApiClient } from "./script.types.d.ts";

declare const truapi: TrUApiClient;

assert.equal(process.cwd(), import.meta.dir, "Managed scripts use their project directory");
assert(process.env.TRUAPI_FRAME_URL?.startsWith("ws+unix:"), "Use the default Unix socket");
const accounts = await getAccountsProvider();
assert(accounts, "SDK discovers the host account API without binding");
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
assert(storage, "SDK discovers host storage without binding");
await storage.writeString("sdk-e2e", "shared");
assert.equal(await storage.readString("sdk-e2e"), "shared");
const rawStored = await truapi.localStorage.read({ key: "sdk-e2e" });
assert(rawStored.isOk(), "Raw client reads SDK storage from the same product");
assert.equal(rawStored.value.value, "0x736861726564");
await storage.clear("sdk-e2e");
for (let line = 0; line < 80; line++) console.log("Script output line", line);
console.log("SDK_E2E_OK");
`;

function seedSigningAccount(state) {
  const directory = join(state, "v2");
  mkdirSync(directory, { recursive: true });
  // Same public test identity as signing_host_cli.rs; bypasses network onboarding.
  writeFileSync(
    join(directory, "accounts.json"),
    JSON.stringify({
      version: 1,
      accounts: [
        {
          name: "sdk-e2e",
          network: "paseo-next-v2",
          mnemonic:
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
          lite_username: "cachedalice.01",
          public_key_hex: "0x00",
          address: "5GrwvaEF5zXb26Fz9rcQpDWSKfwVwqNxyvE9uZunJMtBEw2s",
          created_at_unix: 1,
          attested: true,
        },
      ],
    }),
  );
}

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
      let nextPage = Date.now() + 500;
      let pages = 0;
      while (Date.now() < deadline) {
        if (output.length > 0 && Date.now() >= nextRedraw) {
          // Resizing exposes complete frames instead of Ratatui character deltas.
          child.kill("SIGUSR1");
          nextRedraw = Date.now() + 1000;
        }
        const frameStart = output.lastIndexOf("\x1b[2J");
        const currentFrame = stripVTControlCharacters(
          output.slice(frameStart),
        ).replace(/\s/g, "");
        const running = currentFrame.includes("Running/script");
        const activity = stripVTControlCharacters(
          output.slice(Math.max(frameStart, start)),
        )
          .replace(/\s/g, "")
          .match(/Script(running|finished|failed)/g)
          ?.at(-1);
        const completion = expected === "Script finished";
        if (completion && !running && activity === "Scriptfailed") {
          throw new Error(`Script failed:\n${this.output.slice(-16000)}`);
        }
        if (
          (completion
            ? activity === "Scriptfinished"
            : stripVTControlCharacters(output.slice(start))
                .replace(/\s/g, "")
                .includes(expected.replace(/\s/g, ""))) &&
          (!idle || !running)
        ) {
          if (pages) child.stdin.write("\x1b[6~".repeat(pages));
          return;
        }
        // Completion updates the original activity above potentially long output.
        if (completion && !running && pages < 20 && Date.now() >= nextPage) {
          child.stdin.write("\x1b[5~");
          pages++;
          nextPage = Date.now() + 500;
        }
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
  const tools = join(repoRoot, ".agent/tools");
  mkdirSync(tools, { recursive: true });
  const workspace = mkdtempSync(join(tools, "sdk-e2e-"));
  const project = join(workspace, "project with spaces");
  const retainedProject = join(workspace, "retained project");
  const state = join(workspace, "state");
  const binary = join(workspace, "bin/truapi-host");
  const release = await startReleaseServer();
  release.publish(version, target, readFileSync(archive));
  const environment = {
    ...process.env,
    ...installEnvironment(workspace, release.baseUrl),
    TRUAPI_HOST_NO_UPDATE: "1",
    BUN_INSTALL_CACHE_DIR: join(workspace, "bun-cache"),
    VISUAL: "true",
    EDITOR: "true",
  };
  for (const name of ["TRUAPI_HOST_RUNNER", "HOST_CLI_SIGNER_MNEMONIC"])
    delete environment[name];
  const args = [
    "pairing-host",
    "--product-id",
    "my-app.dot",
    "--base-path",
    state,
    "--auto-accept",
  ];
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
    terminal = terminalSession(
      binary,
      args,
      {
        ...environment,
        npm_config_registry: "http://127.0.0.1:1",
        BUN_CONFIG_REGISTRY: "http://127.0.0.1:1",
      },
      workspace,
    );
    await terminal.waitFor("Listening for product frames");
    terminal.send(`/script --new ${retainedProject}\r`);
    await terminal.waitFor(
      "Project retained; fix the package or network error",
      0,
      180000,
    );
    const retainedScript = readFileSync(
      join(retainedProject, "script.ts"),
      "utf8",
    );
    const retainedManifest = readFileSync(
      join(retainedProject, "package.json"),
      "utf8",
    );
    terminal.send("/quit\r");
    assert.equal(await terminal.waitForExit(), 0);
    writeFileSync(join(workspace, "failed-install.log"), terminal.output);

    terminal = terminalSession(binary, args, environment, workspace);
    await terminal.waitFor("Listening for product frames");
    terminal.send("/script --edit\r");
    await terminal.waitFor("Script saved", 0, 180000);
    assert.equal(
      readFileSync(join(retainedProject, "script.ts"), "utf8"),
      retainedScript,
    );
    assert.equal(
      readFileSync(join(retainedProject, "package.json"), "utf8"),
      retainedManifest,
    );
    console.log(
      "  ok    Failed dependency setup retains the project and retries after reopening",
    );
    terminal.send(`/script --new ${project}\r`);
    await terminal.waitFor("Connected accounts: []", 0, 180000);
    await terminal.waitFor("Last visit:");
    await terminal.waitFor("Script finished");
    const scriptPath = join(project, "script.ts");
    const manifestPath = join(project, "package.json");
    const templates = join(repoRoot, "rust/crates/truapi-host-cli/js");
    const starter = readFileSync(scriptPath, "utf8");
    const manifest = readFileSync(manifestPath, "utf8");
    assert.equal(
      starter,
      readFileSync(join(templates, "sdk-script.ts"), "utf8"),
    );
    assert.deepEqual(
      JSON.parse(manifest),
      JSON.parse(readFileSync(join(templates, "script-package.json"), "utf8")),
    );
    console.log(
      "  ok    Unchanged default project installs and runs the exact signed-out quickstart",
    );
    await checkedRun(
      "Generated SDK quickstart typechecks",
      "bun",
      ["run", "typecheck"],
      {
        env: environment,
        cwd: project,
      },
    );
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
      "  ok    SDK and raw account errors, subscription, and shared product storage",
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
    assert.equal(readFileSync(manifestPath, "utf8"), manifest);
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

    writeFileSync(scriptPath, starter);
    const copiedProject = join(workspace, "copied project");
    cpSync(project, copiedProject, {
      recursive: true,
      filter: (path) => path !== join(project, "node_modules"),
    });
    await checkedRun(
      "Copied project installs offline from the package cache",
      "bun",
      ["install", "--offline", "--frozen-lockfile"],
      {
        env: environment,
        cwd: copiedProject,
      },
    );
    assert.equal(
      readFileSync(join(copiedProject, "package.json"), "utf8"),
      manifest,
    );
    assert.equal(readFileSync(join(copiedProject, "bun.lock"), "utf8"), lock);
    const copiedScript = join(copiedProject, "script.ts");
    const relativeRunner = await checkedRun(
      "Copied quickstart runs with a relative installed runner override",
      binary,
      [...args, "--script", copiedScript],
      {
        env: { ...environment, TRUAPI_HOST_RUNNER: "share/current/runner.js" },
        cwd: workspace,
      },
    );
    assert.match(relativeRunner.stdout + relativeRunner.stderr, /Last visit:/);

    const signingState = join(workspace, "signing-state");
    seedSigningAccount(signingState);
    writeFileSync(
      copiedScript,
      `${starter}\nif (accounts.length === 0) throw new Error("SDK_E2E_NO_ACCOUNT");\nconsole.log("SDK_E2E_SIGNED_IN_OK");\n`,
    );
    const signedIn = await checkedRun(
      "Exact quickstart connects a local signing account and persists storage",
      binary,
      [
        "signing-host",
        "--product-id",
        "my-app.dot",
        "--base-path",
        signingState,
        "--account",
        "sdk-e2e",
        "--auto-accept",
        "--script",
        copiedScript,
      ],
      { env: environment, cwd: workspace },
    );
    writeFileSync(
      join(workspace, "signed-in.log"),
      signedIn.stdout + signedIn.stderr,
    );
    assert.match(signedIn.stdout + signedIn.stderr, /SDK_E2E_SIGNED_IN_OK/);
    assert.match(signedIn.stdout + signedIn.stderr, /Last visit:/);
    writeFileSync(copiedScript, starter);

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
    assert.match(failure.stdout + failure.stderr, /SDK_E2E_UNDERLYING_FAILURE/);
    assert.match(failure.stdout + failure.stderr, /script\.ts/);
    writeFileSync(scriptPath, starter);
    console.log(
      "  ok    Script errors preserve nonzero status, source location, and cause",
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
