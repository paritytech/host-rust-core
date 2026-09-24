// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { resolve } from "node:path";
import { capture, captureOptional, run } from "./process.mjs";

/** Development bundle id of the Polkadot iOS app. */
export const DEFAULT_BUNDLE = "io.pcf.polkadotapp.develop";

/** Default DerivedData location of the sibling polkadot-app-ios-v2 checkout. */
export function defaultAppPath(repoRoot) {
  return resolve(
    repoRoot,
    "../polkadot-app-ios-v2/build/DerivedData/Build/Products/Debug-iphonesimulator/polkadot-app.app",
  );
}

/** App-group container id matching the app bundle's configuration. */
export function appGroupId(bundle) {
  return bundle.endsWith(".develop")
    ? "group.pcf.polkadotapp.develop"
    : "group.pcf.polkadotapp";
}

/** Read one key from a plist; undefined when the file or key is missing. */
export function readPlistValue(plist, key) {
  return captureOptional("/usr/libexec/PlistBuddy", [
    "-c",
    `Print :${key}`,
    plist,
  ]);
}

export function selectSimulator() {
  const requested =
    process.env.TRUAPI_IOS_E2E_DEVICE ?? process.env.IOS_SIMULATOR_DEVICE;
  const simulatorList = JSON.parse(
    capture("xcrun", ["simctl", "list", "devices", "available", "-j"]),
  );
  const selected = selectSimulatorFromList(simulatorList, requested);

  if (!selected) {
    throw new Error(
      requested
        ? `Requested simulator is unavailable: ${requested}`
        : "No available iPhone simulator found",
    );
  }
  return selected;
}

export function selectSimulatorFromList(simulatorList, requested) {
  const available = Object.values(simulatorList.devices)
    .flat()
    .filter((candidate) => candidate.isAvailable);
  if (requested) {
    return available.find(
      (candidate) =>
        candidate.udid === requested || candidate.name === requested,
    );
  }

  const preparedE2E = available.find(
    (candidate) =>
      candidate.name.includes("TrUAPI") && candidate.name.includes("E2E"),
  );
  if (preparedE2E) {
    return preparedE2E;
  }

  const iPhones = available.filter((candidate) =>
    candidate.name.startsWith("iPhone"),
  );
  return (
    iPhones.find((candidate) => candidate.state === "Booted") ?? iPhones[0]
  );
}

export function bootAndInstallApp(app) {
  const device = selectSimulator();
  run(
    "open",
    ["-a", "Simulator", "--args", "-CurrentDeviceUDID", device.udid],
    {
      stdio: "ignore",
    },
  );
  if (device.state !== "Booted") {
    run("xcrun", ["simctl", "boot", device.udid]);
  }
  run("xcrun", ["simctl", "bootstatus", device.udid, "-b"]);
  run("xcrun", ["simctl", "install", device.udid, app]);
  return device;
}
