import assert from "node:assert/strict";
import test from "node:test";

import {
  parsePackageLines,
  waitForPublishedVersions,
} from "./npm-registry.mjs";

const packagesBlock = `@parity/truapi|js/packages/truapi|0.10.0|@parity/truapi@0.10.0
@parity/truapi-host|js/packages/truapi-host|0.7.0|@parity/truapi-host@0.7.0
`;

/**
 * Fake registry. `statuses` maps "<name>@<version>" to either a single status
 * code or an array of codes returned one per poll.
 */
function fakeRegistry(statuses) {
  const calls = [];
  return {
    calls,
    fetchStatus(name, version) {
      const key = `${name}@${version}`;
      calls.push(key);
      const entry = statuses[key];
      if (Array.isArray(entry)) {
        return Promise.resolve(entry.length > 1 ? entry.shift() : entry[0]);
      }
      return Promise.resolve(entry ?? 404);
    },
  };
}

function countingSleep() {
  const sleep = () => {
    sleep.count += 1;
    return Promise.resolve();
  };
  sleep.count = 0;
  return sleep;
}

const truapi = "@parity/truapi@0.10.0";
const host = "@parity/truapi-host@0.7.0";

test("parsePackageLines reads the workflow's four-field block", () => {
  assert.deepEqual(parsePackageLines(packagesBlock), [
    {
      name: "@parity/truapi",
      path: "js/packages/truapi",
      version: "0.10.0",
      tag: "@parity/truapi@0.10.0",
    },
    {
      name: "@parity/truapi-host",
      path: "js/packages/truapi-host",
      version: "0.7.0",
      tag: "@parity/truapi-host@0.7.0",
    },
  ]);
});

test("parsePackageLines rejects a line that is not four fields", () => {
  assert.throws(
    () => parsePackageLines("@parity/truapi|js/packages/truapi|0.10.0\n"),
    /four fields/,
  );
});

test("resolves on the first poll when every version is already published", async () => {
  const registry = fakeRegistry({ [truapi]: 200, [host]: 200 });
  const sleep = countingSleep();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep,
    timeoutMs: 60_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, true);
  assert.deepEqual(
    result.published.map((entry) => entry.tag),
    [truapi, host],
  );
  assert.deepEqual(result.missing, []);
  assert.equal(sleep.count, 0, "nothing to wait for");
});

test("retries a 404 and sleeps between polls", async () => {
  const registry = fakeRegistry({ [truapi]: 200, [host]: [404, 200] });
  const sleep = countingSleep();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep,
    timeoutMs: 60_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, true);
  assert.equal(sleep.count, 1, "one wait, not a busy loop");
  assert.equal(
    registry.calls.filter((call) => call === truapi).length,
    1,
    "a confirmed package is not polled again",
  );
});

test("returns the confirmed subset alongside the missing one on timeout", async () => {
  const registry = fakeRegistry({ [truapi]: 200, [host]: 404 });
  const sleep = countingSleep();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep,
    timeoutMs: 2_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, false);
  assert.deepEqual(
    result.published.map((entry) => entry.tag),
    [truapi],
    "the package that did publish must still be tagged",
  );
  assert.deepEqual(
    result.missing.map((entry) => entry.tag),
    [host],
  );
});

test("reports every missing package, not only the first", async () => {
  const registry = fakeRegistry({ [truapi]: 404, [host]: 404 });

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep: countingSleep(),
    timeoutMs: 2_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.published, []);
  assert.deepEqual(
    result.missing.map((entry) => entry.tag),
    [truapi, host],
  );
});

test("treats a registry error as not-yet-published and keeps polling", async () => {
  const registry = fakeRegistry({ [truapi]: [500, 200], [host]: 200 });
  const sleep = countingSleep();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep,
    timeoutMs: 60_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, true, "a 500 must not crash the poll");
  assert.equal(sleep.count, 1);
});

test("a rejected fetch is retried rather than thrown", async () => {
  let attempts = 0;
  const fetchStatus = () => {
    attempts += 1;
    return attempts === 1
      ? Promise.reject(new Error("socket hang up"))
      : Promise.resolve(200);
  };

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(
      "@parity/truapi|js/packages/truapi|0.10.0|@parity/truapi@0.10.0\n",
    ),
    fetchStatus,
    sleep: countingSleep(),
    timeoutMs: 60_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, true);
});

test("ok is false while any single package is missing", async () => {
  const registry = fakeRegistry({ [truapi]: 200, [host]: 404 });

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep: countingSleep(),
    timeoutMs: 2_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, false);
  assert.equal(result.published.length, 1);
});
