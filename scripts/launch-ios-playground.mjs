#!/usr/bin/env node
// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import {
  bootAndInstallApp,
  captureOptional,
  delay,
  isLoopback,
  run,
} from "./lib/ios-simulator.mjs";

const repoRoot = resolve(import.meta.dirname, "..");
const bundle =
  process.env.TRUAPI_IOS_E2E_BUNDLE ?? "io.pcf.polkadotapp.develop";
const app =
  process.env.TRUAPI_IOS_E2E_APP ??
  resolve(
    repoRoot,
    "../polkadot-app-ios-v2/build/DerivedData/Build/Products/Debug-iphonesimulator/polkadot-app.app",
  );
const productHost =
  process.env.TRUAPI_IOS_E2E_PRODUCT_HOST ?? "truapi-playground.dot";
const productUrl =
  process.env.TRUAPI_IOS_E2E_PRODUCT_URL ?? "http://localhost:3100";

if (!existsSync(app)) {
  throw new Error(`iOS app bundle not found: ${app}`);
}

const playgroundProcess = await ensurePlayground();
const device = bootAndInstallApp(app);
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
    await delay(500);
  }
  throw new Error(`Timed out waiting for TrUAPI playground at ${productUrl}`);
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
