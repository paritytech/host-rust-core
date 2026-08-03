// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { spawnSync } from "node:child_process";

export function capture(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with ${result.status}`,
    );
  }
  return result.stdout;
}

export function captureOptional(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : undefined;
}

export function run(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: "inherit", ...options });
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with ${result.status}`,
    );
  }
}

export function selectSimulator() {
  const requested =
    process.env.TRUAPI_IOS_E2E_DEVICE ?? process.env.IOS_SIMULATOR_DEVICE;
  const simulatorList = JSON.parse(
    capture("xcrun", ["simctl", "list", "devices", "available", "-j"]),
  );
  const devices = Object.values(simulatorList.devices)
    .flat()
    .filter(
      (candidate) =>
        candidate.isAvailable && candidate.name.startsWith("iPhone"),
    );
  const selected = requested
    ? devices.find(
        (candidate) =>
          candidate.udid === requested || candidate.name === requested,
      )
    : (devices.find((candidate) => candidate.state === "Booted") ?? devices[0]);

  if (!selected) {
    throw new Error(
      requested
        ? `Requested iPhone simulator is unavailable: ${requested}`
        : "No available iPhone simulator found",
    );
  }
  return selected;
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

export function isLoopback(url) {
  return ["localhost", "127.0.0.1", "::1", "[::1]"].includes(url.hostname);
}

export function delay(milliseconds) {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, milliseconds));
}
