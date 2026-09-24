// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { spawn, spawnSync } from "node:child_process";
import { existsSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { waitFor } from "./process.mjs";

export const DEFAULT_AVD = "truapi-chat-e2e";

export const DEFAULT_PACKAGE = "com.example.polkadot.debug";

/** Headless emulator flags; the data partition is wiped on every boot. */
const EMULATOR_HEADLESS_ARGS = [
  "-no-window",
  "-no-audio",
  "-no-boot-anim",
  "-no-snapshot",
  "-memory",
  "4096",
  "-gpu",
  "swiftshader_indirect",
];

const DEFAULT_ADB_TIMEOUT_MS = 30_000;
const BOOT_TIMEOUT_MS = 300_000;
const INSTALL_TIMEOUT_MS = 900_000;
const ADB_MAX_BUFFER = 256 * 1024 * 1024;
const ADB_RESTART_THROTTLE_MS = 15_000;

const SDK_FALLBACKS = [
  "/opt/homebrew/share/android-commandlinetools",
  "/usr/local/share/android-commandlinetools",
  process.env.HOME ? resolve(process.env.HOME, "Library/Android/sdk") : "",
  process.env.HOME ? resolve(process.env.HOME, "Android/Sdk") : "",
].filter(Boolean);

function androidSdkRoot() {
  const configured = process.env.ANDROID_HOME ?? process.env.ANDROID_SDK_ROOT;
  if (configured) {
    if (!existsSync(configured)) {
      throw new Error(`ANDROID_HOME points at a missing directory: ${configured}`);
    }
    return configured;
  }
  const found = SDK_FALLBACKS.find((candidate) => existsSync(candidate));
  if (!found) {
    throw new Error(
      "Android SDK not found. Set ANDROID_HOME (or ANDROID_SDK_ROOT), " +
        `e.g. ${SDK_FALLBACKS[0]}`,
    );
  }
  return found;
}

function sdkTool(relative, hint) {
  const tool = resolve(androidSdkRoot(), relative);
  if (!existsSync(tool)) {
    throw new Error(`${relative} not found under the Android SDK: ${tool}\n${hint}`);
  }
  return tool;
}

function adbPath() {
  return sdkTool(
    "platform-tools/adb",
    "Install it with: sdkmanager 'platform-tools'",
  );
}

function emulatorPath() {
  return sdkTool("emulator/emulator", "Install it with: sdkmanager 'emulator'");
}

/** `ChatExtension:<extensionId>:<roomId>` as `ChatId.forExtensionRoom` encodes it, hex for `X'…'`. */
export function chatIdHex(extensionId, roomId) {
  return Buffer.from(`ChatExtension:${extensionId}:${roomId}`, "utf8")
    .toString("hex")
    .toUpperCase();
}

export function parseDeviceList(output) {
  return (output ?? "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(
      (line) =>
        line &&
        !line.startsWith("List of devices") &&
        !line.startsWith("*") &&
        !line.startsWith("adb server"),
    )
    .map((line) => line.split(/\s+/))
    .filter((parts) => parts.length >= 2)
    .map(([serial, state]) => ({ serial, state }));
}

export function selectDevice(output, requested) {
  const devices = parseDeviceList(output);
  if (requested) {
    return devices.find(
      (device) => device.serial === requested && device.state === "device",
    );
  }
  return devices.find((device) => device.state === "device");
}

const ADB_UNHEALTHY_MARKERS = [
  "device offline",
  "device still authorizing",
  "device unauthorized",
  "protocol fault",
  "error: closed",
  "cannot connect to daemon",
  "daemon not running",
  "no devices/emulators found",
  "device not found",
];

/** Detect the failures a `kill-server`/`start-server` cycle can recover from. */
export function isAdbUnhealthy({
  status,
  stdout = "",
  stderr = "",
  timedOut = false,
} = {}) {
  if (timedOut) {
    return true;
  }
  if (status === 0) {
    return false;
  }
  const text = `${stdout}\n${stderr}`.toLowerCase();
  return ADB_UNHEALTHY_MARKERS.some((marker) => text.includes(marker));
}

const LOGCAT_THREADTIME =
  /^\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\s+\d+\s+\d+\s+([VDIWEF])\s+(\S.*?)\s*:\s?(.*)$/;

export function parseLogcatLine(line) {
  const match = LOGCAT_THREADTIME.exec(line ?? "");
  if (!match) {
    return undefined;
  }
  return { level: match[1], tag: match[2], message: match[3] };
}

export function findLogcatMessage(output, needle) {
  for (const line of (output ?? "").split(/\r?\n/)) {
    const entry = parseLogcatLine(line);
    if (entry?.message.includes(needle)) {
      return entry;
    }
  }
  return undefined;
}

export function findLogcatError(output, tag) {
  for (const line of (output ?? "").split(/\r?\n/)) {
    const entry = parseLogcatLine(line);
    if (!entry || (tag && entry.tag !== tag)) {
      continue;
    }
    if (/^error\b/i.test(entry.message)) {
      return entry;
    }
  }
  return undefined;
}

export function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

export function shellCommand(parts) {
  return parts.map(shellQuote).join(" ");
}

export function parseAvdList(output) {
  return (output ?? "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !/\s/.test(line) && !line.startsWith("INFO"));
}

/** Decode rows selected as `hex(column)`; hex survives sqlite3's list mode. */
export function decodeSqliteHexRows(output) {
  return (output ?? "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((row) => /^(?:[0-9A-Fa-f]{2})+$/.test(row))
    .map((row) => Buffer.from(row, "hex").toString("utf8"));
}

/** The rejection `am broadcast` printed, if any; it reports result=0 either way. */
export function parseBroadcastResult(output) {
  const error = (output ?? "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) =>
      /^(Error|Exception|java\.lang\.|Bad component)|does not exist|Unable to/i.test(
        line,
      ),
    );
  return { error };
}

let lastAdbRestart = 0;

function runAdbOnce(args, { timeoutMs, encoding }) {
  const result = spawnSync(adbPath(), args, {
    encoding,
    timeout: timeoutMs,
    maxBuffer: ADB_MAX_BUFFER,
  });
  const timedOut =
    result.error?.code === "ETIMEDOUT" ||
    (result.signal !== null && result.signal !== undefined);
  return {
    status: result.status,
    stdout: result.stdout ?? (encoding === "buffer" ? Buffer.alloc(0) : ""),
    stderr:
      encoding === "buffer"
        ? (result.stderr ?? Buffer.alloc(0)).toString("utf8")
        : (result.stderr ?? ""),
    timedOut,
  };
}

function restartAdbServer() {
  const now = Date.now();
  if (now - lastAdbRestart < ADB_RESTART_THROTTLE_MS) {
    return false;
  }
  lastAdbRestart = now;
  for (const command of ["kill-server", "start-server"]) {
    spawnSync(adbPath(), [command], {
      encoding: "utf8",
      timeout: DEFAULT_ADB_TIMEOUT_MS,
    });
  }
  return true;
}

/** Run one adb command with a timeout; never throws for a non-zero exit. */
function adb(args, { serial, timeoutMs = DEFAULT_ADB_TIMEOUT_MS, encoding = "utf8" } = {}) {
  const full = serial ? ["-s", serial, ...args] : args;
  let result = runAdbOnce(full, { timeoutMs, encoding });
  if (isAdbUnhealthy(result) && restartAdbServer()) {
    result = runAdbOnce(full, { timeoutMs, encoding });
  }
  return result;
}

function adbOrThrow(args, options = {}) {
  const result = adb(args, options);
  if (result.status !== 0) {
    const reason = result.timedOut
      ? `timed out after ${options.timeoutMs ?? DEFAULT_ADB_TIMEOUT_MS}ms`
      : `exit ${result.status}`;
    const detail = `${result.stderr}`.trim() || `${result.stdout}`.trim();
    throw new Error(`adb ${args.join(" ")} failed (${reason})${detail ? `: ${detail}` : ""}`);
  }
  return result.stdout;
}

function adbShell(serial, parts, options = {}) {
  return adb(["shell", shellCommand(parts)], { serial, ...options });
}

function onlineDevice(requested) {
  const result = adb(["devices"]);
  if (result.status !== 0) {
    return undefined;
  }
  return selectDevice(result.stdout, requested);
}

function listAvds() {
  const result = spawnSync(emulatorPath(), ["-list-avds"], {
    encoding: "utf8",
    timeout: DEFAULT_ADB_TIMEOUT_MS,
  });
  return parseAvdList(result.stdout);
}

function startEmulator(avd, extraArgs = []) {
  const available = listAvds();
  if (!available.includes(avd)) {
    throw new Error(
      `AVD not found: ${avd}. Available: ${available.join(", ") || "none"}.\n` +
        `Create it with: avdmanager create avd -n ${avd} -k "system-images;android-36;google_apis;arm64-v8a"`,
    );
  }
  const child = spawn(
    emulatorPath(),
    ["-avd", avd, ...EMULATOR_HEADLESS_ARGS, ...extraArgs],
    { detached: true, stdio: "ignore" },
  );
  child.unref();
  return child;
}

function waitForBootCompleted(serial, timeoutMs) {
  return waitFor(
    () => {
      const result = adbShell(serial, ["getprop", "sys.boot_completed"]);
      return result.status === 0 && result.stdout.trim() === "1";
    },
    {
      timeoutMs,
      intervalMs: 2_000,
      message: () =>
        `Timed out waiting for sys.boot_completed=1 on ${serial} after ${timeoutMs}ms`,
    },
  );
}

export async function ensureEmulator({
  avd = DEFAULT_AVD,
  serial,
  timeoutMs = BOOT_TIMEOUT_MS,
  log = () => {},
} = {}) {
  let device = onlineDevice(serial);
  if (!device) {
    log(`no device online; booting AVD ${avd} headless`);
    startEmulator(avd);
    device = await waitFor(() => onlineDevice(serial), {
      timeoutMs,
      intervalMs: 2_000,
      message: () =>
        `Timed out waiting for AVD ${avd} to attach to adb after ${timeoutMs}ms`,
    });
  }
  await waitForBootCompleted(device.serial, timeoutMs);
  return device.serial;
}

/** Install unconditionally: `-no-snapshot` wipes the data partition each boot. */
export function installApk(serial, apk, timeoutMs = INSTALL_TIMEOUT_MS) {
  if (!existsSync(apk)) {
    throw new Error(`APK not found: ${apk}`);
  }
  const output = adbOrThrow(["install", "-r", "-t", apk], {
    serial,
    timeoutMs,
  });
  if (!/Success/.test(output)) {
    throw new Error(`adb install did not report success:\n${output.trim()}`);
  }
  return output;
}

export function clearAppData(serial, packageName) {
  const result = adbShell(serial, ["pm", "clear", packageName]);
  const output = `${result.stdout}${result.stderr}`;
  if (result.status !== 0 || !/Success/.test(output)) {
    throw new Error(`pm clear ${packageName} failed:\n${output.trim()}`);
  }
  return output;
}

export function reversePort(serial, port) {
  return adbOrThrow(["reverse", `tcp:${port}`, `tcp:${port}`], { serial });
}

export function removeReversePort(serial, port) {
  return adb(["reverse", "--remove", `tcp:${port}`], { serial });
}

export function grantPermission(serial, packageName, permission) {
  const result = adbShell(serial, ["pm", "grant", packageName, permission]);
  // Not what is under test, so a refused grant must not fail the run.
  return { granted: result.status === 0, output: `${result.stdout}${result.stderr}`.trim() };
}

/** Send a debug-hook broadcast; a freshly installed app is still stopped. */
export function sendBroadcast(serial, { action, component, extras = [] }) {
  const parts = ["am", "broadcast", "--include-stopped-packages", "-a", action];
  if (component) {
    parts.push("-n", component);
  }
  for (const extra of extras) {
    parts.push(...extra);
  }
  const result = adbShell(serial, parts);
  const output = `${result.stdout}\n${result.stderr}`;
  return { ...parseBroadcastResult(output), output: output.trim() };
}

export function startActivity(serial, component) {
  const result = adbShell(serial, ["am", "start", "-n", component]);
  const output = `${result.stdout}\n${result.stderr}`;
  if (result.status !== 0 || /Error|does not exist/i.test(output)) {
    throw new Error(`am start -n ${component} failed:\n${output.trim()}`);
  }
  return output;
}

export function startDeepLink(serial, uri) {
  const result = adbShell(serial, [
    "am",
    "start",
    "-a",
    "android.intent.action.VIEW",
    "-d",
    uri,
  ]);
  const output = `${result.stdout}\n${result.stderr}`;
  if (result.status !== 0 || /Error|does not exist/i.test(output)) {
    throw new Error(`am start -d ${uri} failed:\n${output.trim()}`);
  }
  return output;
}

export function clearLogcat(serial) {
  return adb(["logcat", "-c"], { serial });
}

function dumpLogcat(serial, tags) {
  const filters = tags.map((tag) => `${tag}:V`);
  const result = adb(["logcat", "-d", "-v", "threadtime", ...filters, "*:S"], {
    serial,
  });
  return result.status === 0 ? result.stdout : "";
}

export function waitForLogcatMessage(
  serial,
  { tags, marker, timeoutMs, errorTag, hint },
) {
  return waitFor(
    () => {
      const output = dumpLogcat(serial, tags);
      if (errorTag) {
        const failure = findLogcatError(output, errorTag);
        if (failure) {
          throw new Error(
            `${errorTag} reported a failure while waiting for ${JSON.stringify(marker)}: ${failure.message}`,
          );
        }
      }
      return findLogcatMessage(output, marker);
    },
    {
      timeoutMs,
      intervalMs: 1_000,
      message: () =>
        `Timed out after ${timeoutMs}ms waiting for ${JSON.stringify(marker)} on logcat tags ${tags.join(", ")}${hint ? `\n${hint}` : ""}`,
    },
  );
}

export function runAsSqlite(serial, packageName, database, sql) {
  const result = adbShell(serial, [
    "run-as",
    packageName,
    "sqlite3",
    database,
    sql,
  ]);
  const output = `${result.stdout}${result.stderr}`;
  if (result.status !== 0 || /run-as:|Error:|not debuggable|unknown package/i.test(output)) {
    throw new Error(
      `run-as ${packageName} sqlite3 ${database} failed:\n${output.trim()}`,
    );
  }
  return result.stdout;
}

export function screencap(serial, destination) {
  const result = adb(["exec-out", "screencap", "-p"], {
    serial,
    encoding: "buffer",
  });
  if (result.status !== 0 || result.stdout.length === 0) {
    throw new Error(
      `adb exec-out screencap failed: ${result.stderr.trim() || `exit ${result.status}`}`,
    );
  }
  writeFileSync(destination, result.stdout);
  return destination;
}

export function forceStop(serial, packageName) {
  adbShell(serial, ["am", "force-stop", packageName]);
}

/** Wait until the package has a live process; `am start` returns before it exists. */
export function waitForProcess(
  serial,
  packageName,
  timeoutMs = DEFAULT_ADB_TIMEOUT_MS,
) {
  return waitFor(
    () => {
      const result = adbShell(serial, ["pidof", packageName]);
      const pid = String(result.stdout ?? "").trim();
      return /^\d+$/.test(pid) ? Number(pid) : undefined;
    },
    {
      timeoutMs,
      intervalMs: 250,
      message: () => `${packageName} has no process after ${timeoutMs}ms`,
    },
  );
}
