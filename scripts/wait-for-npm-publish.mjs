#!/usr/bin/env node
import { appendFileSync, readFileSync } from "node:fs";

import {
  parsePackageLines,
  reportConfirmation,
  waitForPublishedVersions,
} from "./lib/npm-registry.mjs";

/**
 * Wait until every released package is installable from npm.
 *
 * Reads release.yml's `name|path|version|tag` block on stdin:
 *   printf '%s' "$PACKAGES" | node scripts/wait-for-npm-publish.mjs
 *
 * Writes the confirmed subset to $GITHUB_OUTPUT as `published`, in the same
 * format, so the tagging steps can consume it. Exits non-zero if any package
 * is still missing.
 *
 * Override the poll bounds with NPM_PUBLISH_TIMEOUT_MS and
 * NPM_PUBLISH_INTERVAL_MS. Both must be a positive number of milliseconds.
 */

const command = "wait-for-npm-publish";
const registry = "https://registry.npmjs.org";
const requestTimeoutMs = 10_000;
const timeoutMs = positiveMs("NPM_PUBLISH_TIMEOUT_MS", 600_000);
const intervalMs = positiveMs("NPM_PUBLISH_INTERVAL_MS", 15_000);

const packages = parse(readFileSync(0, "utf8"));
if (packages.length === 0) {
  fail("no packages on stdin; expected release.yml's packages output");
}

console.log(
  `Waiting up to ${Math.round(timeoutMs / 1000)}s for ${packages.length} package(s) on npm.`,
);

const result = await waitForPublishedVersions({
  packages,
  fetchStatus,
  sleep,
  timeoutMs,
  intervalMs,
});

for (const entry of result.published)
  console.log(`Confirmed ${entry.tag} on npm.`);

process.exit(
  reportConfirmation({
    result,
    writeOutput,
    logError: (message) => console.error(`::error::${message}`),
  }),
);

/**
 * Version-addressed, matching the check npm_publish_automation itself makes.
 * A 404 means not yet published; the packument would need parsing and would
 * not answer for a dist-tagged publish.
 */
async function fetchStatus(name, version) {
  const url = `${registry}/${encodeURIComponent(name)}/${encodeURIComponent(version)}`;
  const response = await fetch(url, {
    // One stalled connection must not spend the whole poll budget.
    signal: AbortSignal.timeout(requestTimeoutMs),
    headers: { "cache-control": "no-cache" },
  });
  return response.status;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function writeOutput(entries) {
  const output = process.env.GITHUB_OUTPUT;
  if (!output) return;
  const lines = entries
    .map(
      ({ name, path, version, tag }) => `${name}|${path}|${version}|${tag}\n`,
    )
    .join("");
  appendFileSync(output, `published<<EOF\n${lines}EOF\n`);
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

function parse(text) {
  try {
    return parsePackageLines(text);
  } catch (error) {
    fail(error.message);
  }
}

function fail(message) {
  console.error(`::error::${command}: ${message}`);
  process.exit(1);
}
