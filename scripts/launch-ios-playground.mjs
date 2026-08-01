#!/usr/bin/env node
// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "..");
const bundle =
  process.env.TRUAPI_IOS_E2E_BUNDLE ?? "io.pcf.polkadotapp.develop";
const app =
  process.env.TRUAPI_IOS_E2E_APP ??
  resolve(
    repoRoot,
    "hosts/ios/build/DerivedData/Build/Products/Debug-iphonesimulator/polkadot-app.app",
  );
const productHost =
  process.env.TRUAPI_IOS_E2E_PRODUCT_HOST ?? "truapi-playground.dot";
const productUrl =
  process.env.TRUAPI_IOS_E2E_PRODUCT_URL ?? "http://localhost:3100";

if (!existsSync(app)) {
  throw new Error(`iOS app bundle not found: ${app}`);
}

const playgroundProcess = await ensurePlayground();
const device = selectSimulator();

run("open", ["-a", "Simulator", "--args", "-CurrentDeviceUDID", device.udid], {
  stdio: "ignore",
});
if (device.state !== "Booted") {
  run("xcrun", ["simctl", "boot", device.udid]);
}
run("xcrun", ["simctl", "bootstatus", device.udid, "-b"]);
run("xcrun", ["simctl", "install", device.udid, app]);
const signingHostSession = readSigningHostSession(device.udid);
run(
  "xcrun",
  ["simctl", "launch", "--terminate-running-process", device.udid, bundle],
  {
    env: {
      ...process.env,
      SIMCTL_CHILD_RUST_BACKTRACE: "1",
      SIMCTL_CHILD_TRUAPI_IOS_E2E_BROWSE: "1",
      SIMCTL_CHILD_TRUAPI_IOS_E2E_PRODUCT_HOST: productHost,
      SIMCTL_CHILD_TRUAPI_IOS_E2E_PRODUCT_URL: productUrl,
    },
  },
);

console.log(
  JSON.stringify({
    device: device.name,
    deviceId: device.udid,
    app,
    bundle,
    productHost,
    productUrl,
    signingHostUsername: signingHostSession.username,
    signingHost: "truapi-host local session",
  }),
);

if (playgroundProcess) {
  console.log("The TrUAPI playground is running; press Ctrl-C to stop it.");
  await keepPlaygroundAlive(playgroundProcess);
}

async function ensurePlayground() {
  const initialProbe = await probePlayground();
  if (initialProbe === "ready") {
    return null;
  }
  if (initialProbe === "wrong-product") {
    throw new Error(
      `${productUrl} is serving a different app; stop it or set TRUAPI_IOS_E2E_PRODUCT_URL`,
    );
  }

  const url = new URL(productUrl);
  if (!isLoopback(url)) {
    throw new Error(`TrUAPI playground is not reachable at ${productUrl}`);
  }

  const port = url.port || (url.protocol === "https:" ? "443" : "80");
  const child = spawn(
    "yarn",
    ["dev", "--hostname", "0.0.0.0", "--port", port],
    {
      cwd: resolve(repoRoot, "playground"),
      env: process.env,
      stdio: "inherit",
    },
  );

  try {
    await waitForPlayground(child);
    return child;
  } catch (error) {
    child.kill("SIGTERM");
    throw error;
  }
}

async function probePlayground() {
  try {
    const response = await fetch(productUrl);
    if (!response.ok) {
      return "unreachable";
    }
    const body = await response.text();
    return body.includes("TrUAPI Playground") ? "ready" : "wrong-product";
  } catch {
    return "unreachable";
  }
}

async function waitForPlayground(child) {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(`TrUAPI playground exited with ${child.exitCode}`);
    }
    if ((await probePlayground()) === "ready") {
      return;
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 500));
  }
  throw new Error(`Timed out waiting for TrUAPI playground at ${productUrl}`);
}

function selectSimulator() {
  const requested =
    process.env.TRUAPI_IOS_E2E_DEVICE ?? process.env.IOS_SIMULATOR_DEVICE;
  const simulatorList = JSON.parse(
    capture("xcrun", ["simctl", "list", "devices", "available", "-j"]),
  );
  const devices = Object.values(simulatorList.devices)
    .flat()
    .filter((device) => device.isAvailable && device.name.startsWith("iPhone"));

  const selected = requested
    ? devices.find(
        (device) => device.udid === requested || device.name === requested,
      )
    : (devices.find((device) => device.state === "Booted") ?? devices[0]);

  if (!selected) {
    throw new Error(
      requested
        ? `Requested iPhone simulator is unavailable: ${requested}`
        : "No available iPhone simulator found",
    );
  }
  return selected;
}

function isLoopback(url) {
  return ["localhost", "127.0.0.1", "::1", "[::1]"].includes(url.hostname);
}

function capture(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with ${result.status}`,
    );
  }
  return result.stdout;
}

function captureOptional(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : undefined;
}

function readSigningHostSession(deviceId) {
  const installedSession = readSessionForBundle(deviceId, bundle);
  if (installedSession.username && installedSession.entropyId) {
    return installedSession;
  }

  const developmentBundle = "io.pcf.polkadotapp.develop";
  if (bundle !== developmentBundle) {
    const developmentSession = readSessionForBundle(
      deviceId,
      developmentBundle,
    );
    if (developmentSession.username && developmentSession.entropyId) {
      console.log(
        `Reusing the registered ${developmentSession.username} simulator session with the TestFlight configuration.`,
      );
      return developmentSession;
    }
  }

  console.warn(
    "No registered iOS username was found on this simulator; complete native onboarding or select a simulator with an existing wallet session.",
  );
  return { username: null, entropyId: null };
}

function readSessionForBundle(deviceId, appBundle) {
  const appData = captureOptional("xcrun", [
    "simctl",
    "get_app_container",
    deviceId,
    appBundle,
    "data",
  ]);
  const username = appData
    ? readPlistValue(
        resolve(
          appData,
          "Library/Preferences",
          `${appBundle}.plist`,
        ),
        "username",
      )
    : undefined;

  const isDevelopment = appBundle.endsWith(".develop");
  const groupId = isDevelopment
    ? "group.pcf.polkadotapp.develop"
    : "group.pcf.polkadotapp";
  const appGroup = captureOptional("xcrun", [
    "simctl",
    "get_app_container",
    deviceId,
    appBundle,
    groupId,
  ]);
  const entropyId = appGroup
    ? readPlistValue(
        resolve(appGroup, "Library/Preferences", `${groupId}.plist`),
        "io.polkadot.app.entropy.id",
      )
    : undefined;

  return {
    username: username || null,
    entropyId: entropyId || null,
  };
}

function readPlistValue(plist, key) {
  return captureOptional("/usr/libexec/PlistBuddy", [
    "-c",
    `Print :${key}`,
    plist,
  ]);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: "inherit", ...options });
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with ${result.status}`,
    );
  }
}

async function keepPlaygroundAlive(child) {
  await new Promise((resolveWait, reject) => {
    const stop = () => child.kill("SIGTERM");
    process.once("SIGINT", stop);
    process.once("SIGTERM", stop);
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      process.removeListener("SIGINT", stop);
      process.removeListener("SIGTERM", stop);
      if (code === 0 || signal === "SIGTERM") {
        resolveWait();
      } else {
        reject(new Error(`TrUAPI playground exited with ${code ?? signal}`));
      }
    });
  });
}
