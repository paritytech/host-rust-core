#!/usr/bin/env node
import { describeFailure, waitForDeployment } from "./lib/central-portal.mjs";

/**
 * Wait until a Central Portal deployment reaches the state a release needs.
 *
 *   node scripts/wait-for-central-publish.mjs --deployment <id> --target PUBLISHED
 *
 * The upload endpoint answers with a deployment id and nothing else, so this is
 * the only proof that Maven Central accepted the bundle. `--target PUBLISHED`
 * is the release path; `--target VALIDATED` is the rehearsal path, where the
 * Portal parks a `USER_MANAGED` deployment until a person releases or drops it.
 *
 * Reads the Portal token from MAVEN_CENTRAL_USERNAME and
 * MAVEN_CENTRAL_PASSWORD. Override the poll bounds with
 * CENTRAL_PUBLISH_TIMEOUT_MS and CENTRAL_PUBLISH_INTERVAL_MS.
 */

const command = "wait-for-central-publish";
const portal = "https://central.sonatype.com";
const requestTimeoutMs = 10_000;
const timeoutMs = positiveMs("CENTRAL_PUBLISH_TIMEOUT_MS", 900_000);
const intervalMs = positiveMs("CENTRAL_PUBLISH_INTERVAL_MS", 15_000);

const deploymentId = flag("deployment");
const target = flag("target") ?? "PUBLISHED";
// An upload that answered 2xx with an empty body would otherwise poll a
// deployment that does not exist until the deadline.
if (!deploymentId) fail("--deployment <id> is required");

const username = required("MAVEN_CENTRAL_USERNAME");
const password = required("MAVEN_CENTRAL_PASSWORD");
const authorization = `Bearer ${Buffer.from(`${username}:${password}`).toString("base64")}`;

console.log(
  `Waiting up to ${Math.round(timeoutMs / 1000)}s for deployment ${deploymentId} to reach ${target}.`,
);

const result = await waitForDeployment({
  deploymentId,
  fetchState,
  sleep,
  timeoutMs,
  intervalMs,
  target,
});

if (!result.ok) {
  console.error(`::error::${command}: ${describeFailure(result)}`);
  process.exit(1);
}
console.log(`Deployment ${deploymentId} reached ${result.state}.`);

async function fetchState(id) {
  const response = await fetch(
    `${portal}/api/v1/publisher/status?id=${encodeURIComponent(id)}`,
    {
      method: "POST",
      headers: { authorization },
      // One stalled connection must not spend the whole poll budget.
      signal: AbortSignal.timeout(requestTimeoutMs),
    },
  );
  // A rejected token never becomes valid by waiting, and treating it as
  // transient would spend the whole deadline before saying so.
  if (response.status === 401 || response.status === 403) {
    fail(`the Portal rejected the token (${response.status})`);
  }
  if (!response.ok) {
    throw new Error(`status endpoint answered ${response.status}`);
  }
  return response.json();
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function flag(name) {
  const at = process.argv.indexOf(`--${name}`);
  return at === -1 ? undefined : process.argv[at + 1];
}

function required(name) {
  const value = process.env[name];
  if (value === undefined || value === "") fail(`${name} must be set`);
  return value;
}

function positiveMs(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    fail(`${name} must be a positive number of milliseconds, got "${raw}"`);
  }
  return value;
}

function fail(message) {
  console.error(`::error::${command}: ${message}`);
  process.exit(1);
}
