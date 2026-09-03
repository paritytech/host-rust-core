import assert from "node:assert/strict";
import test from "node:test";

import {
  announceRelease,
  compareVersions,
  parseMarker,
  parseSubscribers,
  renderIssue,
  routeNotifications,
  selectExistingIssues,
  unlistedPackages,
} from "./consumer-notifications.mjs";

const dotli = "paritytech/dotli-community";
const productSdk = "paritytech/product-sdk";

const subscribers = {
  "@parity/truapi": [dotli, productSdk],
  "@parity/truapi-host": [dotli],
  "@parity/ios-host": [],
};

const truapi = {
  name: "@parity/truapi",
  version: "0.10.0",
  tag: "@parity/truapi@0.10.0",
};
const truapiHost = {
  name: "@parity/truapi-host",
  version: "0.7.0",
  tag: "@parity/truapi-host@0.7.0",
};

test("parseSubscribers rejects configs the workflow could not act on", () => {
  assert.throws(() => parseSubscribers("[]"), /must be an object/);
  assert.throws(
    () => parseSubscribers(JSON.stringify({ "@parity/truapi": {} })),
    /list of repositories/,
  );
  assert.throws(
    () => parseSubscribers(JSON.stringify({ "@parity/truapi": ["dotli"] })),
    /owner\/name/,
  );
  assert.throws(
    () =>
      parseSubscribers(JSON.stringify({ "@parity/truapi": [dotli, dotli] })),
    /listed twice/,
  );
  assert.deepEqual(
    parseSubscribers(JSON.stringify(subscribers)),
    subscribers,
    "a well-formed config passes through unchanged",
  );
});

test("routeNotifications groups every released package a repo subscribes to", () => {
  assert.deepEqual(
    routeNotifications({ packages: [truapi, truapiHost], subscribers }),
    [
      { repo: dotli, packages: [truapi, truapiHost] },
      { repo: productSdk, packages: [truapi] },
    ],
    "dotli gets one combined entry; product-sdk only sees what it pins",
  );
});

test("routeNotifications skips repos with nothing to bump", () => {
  assert.deepEqual(
    routeNotifications({ packages: [truapiHost], subscribers }),
    [{ repo: dotli, packages: [truapiHost] }],
    "product-sdk does not pin truapi-host, so it must not be notified",
  );
});

test("routeNotifications ignores packages nobody subscribes to", () => {
  const iosHost = {
    name: "@parity/ios-host",
    version: "1.2.0",
    tag: "@parity/ios-host@1.2.0",
  };
  const androidHost = {
    name: "@parity/android-host",
    version: "1.2.0",
    tag: "@parity/android-host@1.2.0",
  };
  assert.deepEqual(
    routeNotifications({ packages: [iosHost, androidHost], subscribers }),
    [],
    "a package listed with no repositories, and one absent entirely, both notify nobody",
  );
});

test("unlistedPackages separates a deliberate silence from an unwired target", () => {
  const iosHost = {
    name: "@parity/ios-host",
    version: "1.2.0",
    tag: "@parity/ios-host@1.2.0",
  };
  const androidHost = {
    name: "@parity/android-host",
    version: "1.2.0",
    tag: "@parity/android-host@1.2.0",
  };
  assert.deepEqual(
    unlistedPackages({ packages: [iosHost, androidHost], subscribers }),
    ["@parity/android-host"],
    "ios-host is listed with no repositories on purpose; android-host is simply absent",
  );
});

test("renderIssue names every package and carries a machine-readable marker", () => {
  const issue = renderIssue({
    packages: [truapi, truapiHost],
    sourceRepo: "paritytech/truapi",
    runUrl: "https://github.com/paritytech/truapi/actions/runs/42",
  });

  assert.equal(
    issue.title,
    "Bump @parity/truapi to 0.10.0 and @parity/truapi-host to 0.7.0",
  );
  assert.match(
    issue.body,
    /npm install @parity\/truapi@0\.10\.0 @parity\/truapi-host@0\.7\.0/,
    "one install line covers the whole release",
  );
  assert.match(
    issue.body,
    /releases\/tag\/%40parity%2Ftruapi%400\.10\.0/,
    "release tags contain @ and / and must be percent-encoded",
  );
  assert.match(issue.body, /actions\/runs\/42/, "links back to the run");
  assert.deepEqual(
    parseMarker(issue.body),
    [
      { name: "@parity/truapi", version: "0.10.0" },
      { name: "@parity/truapi-host", version: "0.7.0" },
    ],
    "the marker round-trips so later releases can compare coverage",
  );
});

test("renderIssue keeps a single-package title readable", () => {
  const issue = renderIssue({
    packages: [truapi],
    sourceRepo: "paritytech/truapi",
    runUrl: "https://github.com/paritytech/truapi/actions/runs/42",
  });
  assert.equal(issue.title, "Bump @parity/truapi to 0.10.0");
});

test("parseMarker ignores issues that are not release notifications", () => {
  assert.equal(parseMarker("Please bump truapi, thanks"), null);
});

test("compareVersions orders release cores and ranks prereleases below them", () => {
  assert.equal(compareVersions("0.10.0", "0.9.0"), 1, "10 is not before 9");
  assert.equal(compareVersions("0.9.0", "0.9.0"), 0);
  assert.equal(compareVersions("1.0.0-rc.1", "1.0.0"), -1);
  assert.equal(compareVersions("1.0.0+build.5", "1.0.0"), 0, "build ignored");
});

test("selectExistingIssues closes only issues the new one fully covers", () => {
  const stale = {
    number: 7,
    body: marker([truapi, truapiHost]),
  };
  const partial = {
    number: 8,
    body: marker([
      truapiHost,
      { name: "@parity/truapi", version: "0.10.0", tag: "" },
    ]),
  };

  const selection = selectExistingIssues({
    issues: [stale, partial],
    packages: [{ ...truapi, version: "0.11.0" }],
  });

  assert.deepEqual(
    selection.supersede,
    [],
    "a truapi-only release leaves both open: each still tracks an unbumped truapi-host",
  );
  assert.deepEqual(selection.duplicate, null);
});

test("selectExistingIssues supersedes an issue whose every package moved on", () => {
  const stale = { number: 7, body: marker([truapi]) };

  const selection = selectExistingIssues({
    issues: [stale],
    packages: [{ ...truapi, version: "0.11.0" }, truapiHost],
  });

  assert.deepEqual(selection.supersede, [stale]);
});

test("selectExistingIssues leaves a newer issue open when a backport lands", () => {
  const newer = {
    number: 9,
    body: marker([{ name: "@parity/truapi", version: "0.11.0" }]),
  };

  const selection = selectExistingIssues({
    issues: [newer],
    packages: [{ ...truapi, version: "0.10.1" }],
  });

  assert.deepEqual(
    selection.supersede,
    [],
    "a release-branch patch must never close the issue for a newer version",
  );
});

test("selectExistingIssues reports an exact match so re-runs do not duplicate", () => {
  const existing = { number: 7, body: marker([truapi, truapiHost]) };

  const selection = selectExistingIssues({
    issues: [existing],
    packages: [truapi, truapiHost],
  });

  assert.equal(selection.duplicate, existing);
  assert.deepEqual(
    selection.supersede,
    [],
    "the issue for this very release is not its own predecessor",
  );
});

/**
 * Fake GitHub. `issues` is the listing the replica returns, `byNumber` what an
 * authoritative read by number returns, so a test can make the two disagree the
 * way the real API does.
 */
function fakeApi({ issues = [], byNumber = {}, labelExists = true } = {}) {
  const calls = [];
  let nextNumber = 100;
  return {
    calls,
    async request(method, path, options) {
      calls.push({ method, path, body: options?.body });
      if (method === "GET" && path.endsWith("/labels/truapi-release")) {
        if (labelExists) return { name: "truapi-release" };
        const error = new Error("not found");
        error.status = 404;
        throw error;
      }
      if (method === "GET" && path.endsWith("/issues")) return issues;
      if (method === "GET") {
        const number = Number(path.split("/").at(-1));
        return byNumber[number] ?? { number, state: "open" };
      }
      if (method === "POST" && path.endsWith("/issues")) {
        nextNumber += 1;
        return { number: nextNumber };
      }
      return {};
    },
  };
}

const announce = (api, packages) =>
  announceRelease({
    request: api.request,
    repo: dotli,
    packages,
    sourceRepo: "paritytech/truapi",
    runUrl: "https://example.invalid/run",
  });

test("announceRelease creates the label only when the repository lacks it", async () => {
  const present = fakeApi();
  await announce(present, [truapi]);
  assert.equal(
    present.calls.filter((call) => call.path.endsWith("/labels")).length,
    0,
    "an existing label must not be recreated",
  );

  const absent = fakeApi({ labelExists: false });
  await announce(absent, [truapi]);
  assert.deepEqual(
    absent.calls.find((call) => call.path.endsWith("/labels"))?.body?.name,
    "truapi-release",
    "a repository seeing its first notification gets the label",
  );
});

test("announceRelease skips the whole repository when the release is already announced", async () => {
  const api = fakeApi({
    issues: [{ number: 7, state: "open", body: marker([truapi]) }],
  });

  const result = await announce(api, [truapi]);

  assert.deepEqual(result, {
    created: null,
    title: null,
    duplicate: 7,
    superseded: [],
    skipped: [],
  });
  assert.equal(
    api.calls.filter((call) => call.method === "POST").length,
    0,
    "a re-run must not write anything at all",
  );
});

test("announceRelease comments on and closes the issues it supersedes", async () => {
  const api = fakeApi({
    issues: [{ number: 7, state: "open", body: marker([truapi]) }],
  });

  const result = await announce(api, [{ ...truapi, version: "0.11.0" }]);

  assert.equal(result.created, 101);
  assert.deepEqual(result.superseded, [7]);
  assert.deepEqual(
    api.calls.filter((call) => call.method !== "GET").map((call) => call.path),
    [
      `/repos/${dotli}/issues`,
      `/repos/${dotli}/issues/7/comments`,
      `/repos/${dotli}/issues/7`,
    ],
    "the new issue exists before anything points at it",
  );
  assert.match(
    api.calls.find((call) => call.path.endsWith("/7/comments")).body.body,
    /Superseded by #101\./,
  );
});

test("announceRelease leaves an issue alone when the authoritative read says it is already closed", async () => {
  // The listing is a read replica, so it can still show an issue that an
  // earlier run closed seconds ago. Acting on it would double-comment.
  const api = fakeApi({
    issues: [{ number: 7, state: "open", body: marker([truapi]) }],
    byNumber: { 7: { number: 7, state: "closed" } },
  });

  const result = await announce(api, [{ ...truapi, version: "0.11.0" }]);

  assert.deepEqual(result.superseded, []);
  assert.deepEqual(result.skipped, [7]);
  assert.deepEqual(
    api.calls.filter((call) => call.method !== "GET").map((call) => call.path),
    [`/repos/${dotli}/issues`],
    "a stale listing must not produce a second supersede comment",
  );
});

/** Build the hidden marker the way renderIssue does, for fixture bodies. */
function marker(packages) {
  return renderIssue({
    packages,
    sourceRepo: "paritytech/truapi",
    runUrl: "https://example.invalid/run",
  }).body;
}
