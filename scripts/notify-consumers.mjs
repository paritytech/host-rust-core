#!/usr/bin/env node
import { readFileSync } from "node:fs";

import {
  announceRelease,
  parseSubscribers,
  routeNotifications,
  unlistedPackages,
} from "./lib/consumer-notifications.mjs";
import { parsePackageLines } from "./lib/npm-registry.mjs";

/**
 * Open a "bump TrUAPI" issue on every repository that consumes a package this
 * release published, and close the notifications it supersedes.
 *
 * Reads release.yml's confirmed `name|path|version|tag` block on stdin:
 *   printf '%s' "$PUBLISHED" | node scripts/notify-consumers.mjs
 *
 * Or, to rehearse against a scratch repository:
 *   node scripts/notify-consumers.mjs --repo me/scratch \
 *     --packages '@parity/truapi||0.10.0|@parity/truapi@0.10.0'
 *
 * Needs CONSUMER_NOTIFY_TOKEN to hold a token with `issues: write` on the target
 * repositories. The workflow mints a GitHub App installation token for it; a
 * personal token with the same reach works for running this by hand.
 * A repository that cannot be reached is a warning, not a failed release; the
 * script exits non-zero at the end so the failure is still visible.
 */

const command = "notify-consumers";
const label = "truapi-release";
const requestTimeoutMs = 15_000;
const api = "https://api.github.com";

const token = required("CONSUMER_NOTIFY_TOKEN");
const sourceRepo = required("GITHUB_REPOSITORY");
const runUrl = process.env.GITHUB_RUN_ID
  ? `${process.env.GITHUB_SERVER_URL ?? "https://github.com"}/${sourceRepo}/actions/runs/${process.env.GITHUB_RUN_ID}`
  : `https://github.com/${sourceRepo}/actions`;

const packages = readPackages();
if (packages.length === 0) {
  console.log("No published packages to announce.");
  process.exit(0);
}

const subscribers = readSubscribers();
for (const name of unlistedPackages({ packages, subscribers })) {
  console.log(
    `::warning::${command}: ${name} is missing from .github/consumers.json, so nobody was told about it.`,
  );
}

const notifications = routeNotifications({ packages, subscribers });
if (notifications.length === 0) {
  console.log("No consumer subscribes to any of the published packages.");
  process.exit(0);
}

let failed = false;
for (const notification of notifications) {
  try {
    await notify(notification);
  } catch (error) {
    failed = true;
    console.log(
      `::warning::${command}: ${notification.repo}: ${error.message}`,
    );
  }
}
process.exit(failed ? 1 : 0);

/** Announce one release to one repository and report what changed. */
async function notify({ repo, packages }) {
  const result = await announceRelease({
    request,
    repo,
    packages,
    sourceRepo,
    runUrl,
  });

  if (result.duplicate !== null) {
    console.log(`${repo}#${result.duplicate} already announces this release.`);
    return;
  }
  console.log(`Opened ${repo}#${result.created}: ${result.title}`);
  for (const number of result.superseded) {
    console.log(`Closed ${repo}#${number} as superseded.`);
  }
  for (const number of result.skipped) {
    console.log(`${repo}#${number} was already closed; left alone.`);
  }
}

async function request(method, path, { query, body } = {}) {
  const url = new URL(`${api}${path}`);
  for (const [key, value] of Object.entries(query ?? {})) {
    url.searchParams.set(key, value);
  }
  const response = await fetch(url, {
    method,
    signal: AbortSignal.timeout(requestTimeoutMs),
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${token}`,
      "x-github-api-version": "2022-11-28",
      ...(body === undefined ? {} : { "content-type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!response.ok) {
    const detail = await response.text();
    const error = new Error(
      `${method} ${path} responded ${response.status}: ${detail}`,
    );
    error.status = response.status;
    throw error;
  }
  return response.json();
}

/**
 * `--repo` sends the whole release to one repository, so the workflow's
 * dry run can rehearse against a scratch repository.
 */
function readSubscribers() {
  const override = flag("repo");
  if (override !== undefined) {
    return parseSubscribers(
      JSON.stringify(
        Object.fromEntries(packages.map(({ name }) => [name, [override]])),
      ),
    );
  }
  try {
    return parseSubscribers(readFileSync(".github/consumers.json", "utf8"));
  } catch (error) {
    fail(`.github/consumers.json: ${error.message}`);
  }
}

function readPackages() {
  const inline = flag("packages");
  try {
    return parsePackageLines(inline ?? readFileSync(0, "utf8"));
  } catch (error) {
    fail(error.message);
  }
}

function flag(name) {
  const at = process.argv.indexOf(`--${name}`);
  return at === -1 ? undefined : process.argv[at + 1];
}

function required(name) {
  const value = process.env[name];
  if (value === undefined || value === "") {
    fail(`${name} must be set`);
  }
  return value;
}

function fail(message) {
  console.error(`::error::${command}: ${message}`);
  process.exit(1);
}
