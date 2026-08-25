import assert from "node:assert/strict";
import test from "node:test";

import {
  parsePackageLines,
  reportConfirmation,
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

/** Fake clock whose `sleep` advances it, so deadlines need no real waiting. */
function fakeClock() {
  const clock = { elapsed: 0, sleeps: 0 };
  clock.now = () => clock.elapsed;
  clock.sleep = (ms) => {
    clock.sleeps += 1;
    clock.elapsed += ms;
    return Promise.resolve();
  };
  return clock;
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
  const clock = fakeClock();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep: clock.sleep,
    now: clock.now,
    timeoutMs: 60_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, true);
  assert.deepEqual(
    result.published.map((entry) => entry.tag),
    [truapi, host],
  );
  assert.deepEqual(result.missing, []);
  assert.equal(clock.sleeps, 0, "nothing to wait for");
});

test("retries a 404 and sleeps between polls", async () => {
  const registry = fakeRegistry({ [truapi]: 200, [host]: [404, 200] });
  const clock = fakeClock();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep: clock.sleep,
    now: clock.now,
    timeoutMs: 60_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, true);
  assert.equal(clock.sleeps, 1, "one wait, not a busy loop");
  assert.equal(
    registry.calls.filter((call) => call === truapi).length,
    1,
    "a confirmed package is not polled again",
  );
});

test("returns the confirmed subset alongside the missing one on timeout", async () => {
  const registry = fakeRegistry({ [truapi]: 200, [host]: 404 });
  const clock = fakeClock();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep: clock.sleep,
    now: clock.now,
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

  const clock = fakeClock();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep: clock.sleep,
    now: clock.now,
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
  const clock = fakeClock();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep: clock.sleep,
    now: clock.now,
    timeoutMs: 60_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, true, "a 500 must not crash the poll");
  assert.equal(clock.sleeps, 1);
});

test("a rejected fetch is retried rather than thrown", async () => {
  let attempts = 0;
  const fetchStatus = () => {
    attempts += 1;
    return attempts === 1
      ? Promise.reject(new Error("socket hang up"))
      : Promise.resolve(200);
  };

  const clock = fakeClock();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(
      "@parity/truapi|js/packages/truapi|0.10.0|@parity/truapi@0.10.0\n",
    ),
    fetchStatus,
    sleep: clock.sleep,
    now: clock.now,
    timeoutMs: 60_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, true);
});

test("ok is false while any single package is missing", async () => {
  const registry = fakeRegistry({ [truapi]: 200, [host]: 404 });

  const clock = fakeClock();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep: clock.sleep,
    now: clock.now,
    timeoutMs: 2_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, false);
  assert.equal(result.published.length, 1);
});

test("parsePackageLines rejects a trailing separator", () => {
  assert.throws(
    () =>
      parsePackageLines(
        "@parity/truapi|js/packages/truapi|0.10.0|@parity/truapi@0.10.0|\n",
      ),
    /four fields/,
  );
});

test("parsePackageLines rejects a blank version", () => {
  assert.throws(
    () =>
      parsePackageLines("@parity/truapi|js/packages/truapi||@parity/truapi@\n"),
    /must not be blank/,
  );
});

test("stops at the deadline rather than after a fixed attempt count", async () => {
  const registry = fakeRegistry({ [truapi]: 404, [host]: 404 });
  const clock = fakeClock();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep: clock.sleep,
    now: clock.now,
    timeoutMs: 5_000,
    intervalMs: 1_000,
  });

  assert.equal(result.ok, false);
  assert.equal(clock.sleeps, 4, "four waits inside a five second budget");
  assert.equal(clock.elapsed, 4_000, "never sleeps past the deadline");
});

test("a slow poll still ends on the deadline, not on the attempt count", async () => {
  const registry = fakeRegistry({ [truapi]: 404, [host]: 404 });
  const clock = fakeClock();
  // Each round costs 3s of clock on top of the interval, as a slow registry would.
  const slowFetch = (name, version) => {
    clock.elapsed += 1_500;
    return registry.fetchStatus(name, version);
  };

  await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: slowFetch,
    sleep: clock.sleep,
    now: clock.now,
    timeoutMs: 10_000,
    intervalMs: 1_000,
  });

  // The deadline governs. A round in flight can overrun by its request time.
  assert.ok(
    clock.elapsed <= 13_000,
    `deadline plus at most one round, elapsed ${clock.elapsed}ms`,
  );
  assert.ok(clock.sleeps <= 3, `stopped early, ${clock.sleeps} waits`);
});

test("reports why a package could not be confirmed", async () => {
  const clock = fakeClock();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: () => Promise.reject(new Error("registry unreachable")),
    sleep: clock.sleep,
    now: clock.now,
    timeoutMs: 2_000,
    intervalMs: 1_000,
  });

  assert.equal(result.errors.get(truapi), "registry unreachable");

  const logged = [];
  reportConfirmation({
    result,
    writeOutput: () => {},
    logError: (m) => logged.push(m),
  });
  assert.match(
    logged[0],
    /could not be confirmed on npm: registry unreachable/,
  );
});

test("a non-404 status is reported rather than read as absent", async () => {
  const registry = fakeRegistry({ [truapi]: 500, [host]: 500 });
  const clock = fakeClock();

  const result = await waitForPublishedVersions({
    packages: parsePackageLines(packagesBlock),
    fetchStatus: registry.fetchStatus,
    sleep: clock.sleep,
    now: clock.now,
    timeoutMs: 2_000,
    intervalMs: 1_000,
  });

  assert.equal(result.errors.get(truapi), "registry answered 500");
});

test("writes the confirmed subset before reporting a failure", () => {
  const order = [];
  const result = {
    ok: false,
    published: [{ name: "a", path: "p", version: "1", tag: "a@1" }],
    missing: [{ name: "b", path: "p", version: "2", tag: "b@2" }],
    errors: new Map(),
  };

  const code = reportConfirmation({
    result,
    writeOutput: (entries) => order.push(`write:${entries.length}`),
    logError: () => order.push("error"),
  });

  assert.equal(code, 1, "a missing package still fails the caller");
  assert.deepEqual(
    order,
    ["write:1", "error"],
    "output written before the failure",
  );
});
