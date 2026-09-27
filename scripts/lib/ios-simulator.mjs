// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { spawnSync } from "node:child_process";

function capture(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with ${result.status}`,
    );
  }
  return result.stdout;
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
