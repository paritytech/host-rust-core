import assert from "node:assert/strict";
import test from "node:test";

import { describeFailure, waitForDeployment } from "./central-portal.mjs";

/**
 * Fake Portal. `states` is either one deployment state or an array returned
 * one per poll, so a test can describe a progression. `errors` is served
 * alongside a FAILED state, as the real status response does.
 */
function fakePortal(states, errors) {
  const queue = Array.isArray(states) ? [...states] : [states];
  const portal = { polls: 0 };
  portal.fetchState = () => {
    portal.polls += 1;
    const state = queue.length > 1 ? queue.shift() : queue[0];
    if (state instanceof Error) return Promise.reject(state);
    return Promise.resolve({
      deploymentId: "dep-1",
      deploymentName: "io.parity:truapi-host-android:1.0.0",
      deploymentState: state,
      ...(errors === undefined ? {} : { errors }),
    });
  };
  return portal;
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

function waiter(portal, clock, overrides = {}) {
  return waitForDeployment({
    deploymentId: "dep-1",
    fetchState: portal.fetchState,
    sleep: clock.sleep,
    now: clock.now,
    timeoutMs: 60_000,
    intervalMs: 5_000,
    target: "PUBLISHED",
    ...overrides,
  });
}

test("polls through the transient states until the deployment is published", async () => {
  const portal = fakePortal(["PENDING", "VALIDATING", "PUBLISHING", "PUBLISHED"]);
  const clock = fakeClock();

  const result = await waiter(portal, clock);

  assert.equal(result.ok, true);
  assert.equal(result.state, "PUBLISHED");
  // Nothing short of PUBLISHED proves the version reached Maven Central, so
  // every earlier state has to keep the loop going.
  assert.equal(portal.polls, 4);
});

test("a USER_MANAGED rehearsal stops at VALIDATED instead of waiting for a human", async () => {
  const portal = fakePortal("VALIDATED");
  const clock = fakeClock();

  const result = await waiter(portal, clock, { target: "VALIDATED" });

  assert.equal(result.ok, true);
  assert.equal(result.state, "VALIDATED");
  // A USER_MANAGED deployment sits in VALIDATED until a person releases or
  // drops it. Polling past it would burn the whole deadline and then report a
  // timeout for a deployment that did exactly what was asked of it.
  assert.equal(portal.polls, 1);
  assert.equal(clock.sleeps, 0);
});

test("accepts a state beyond the target, since an automatic publish can overtake the poll", async () => {
  const portal = fakePortal("PUBLISHED");
  const clock = fakeClock();

  const result = await waiter(portal, clock, { target: "VALIDATED" });

  // Validation and publication are one continuous progression, so "at least
  // validated" is the question. Demanding the exact state would fail a
  // deployment that simply moved on between two polls.
  assert.equal(result.ok, true);
  assert.equal(result.state, "PUBLISHED");
});

test("reports FAILED with the Portal's own reasons and stops polling", async () => {
  const reasons = { "io.parity:truapi-host-android:1.0.0": ["missing signature"] };
  const portal = fakePortal("FAILED", reasons);
  const clock = fakeClock();

  const result = await waiter(portal, clock);

  assert.equal(result.ok, false);
  assert.equal(result.state, "FAILED");
  // Sonatype's own message is the only thing that says which rule the bundle
  // broke, so it has to reach the job log rather than be flattened into
  // "publish failed".
  assert.deepEqual(result.errors, reasons);
  assert.equal(portal.polls, 1);
});

test("fails on an unrecognised state rather than polling until the deadline", async () => {
  const portal = fakePortal("TELEPORTING");
  const clock = fakeClock();

  const result = await waiter(portal, clock);

  // An unknown state means the Portal's API changed under us. Treating it as
  // transient would turn that into an opaque timeout long after the fact.
  assert.equal(result.ok, false);
  assert.equal(result.state, "TELEPORTING");
  assert.match(result.reason, /unrecognised/i);
  assert.equal(portal.polls, 1);
});

test("gives up at the deadline and names the state it was stuck in", async () => {
  const portal = fakePortal("VALIDATING");
  const clock = fakeClock();

  const result = await waiter(portal, clock, {
    timeoutMs: 12_000,
    intervalMs: 5_000,
  });

  assert.equal(result.ok, false);
  assert.equal(result.state, "VALIDATING");
  // Two sleeps fit inside 12s; a third would land past the deadline. A stuck
  // deployment has to fail the job rather than hang it.
  assert.equal(clock.sleeps, 2);
  assert.match(result.reason, /VALIDATING/);
});

test("treats an unreachable Portal as transient, not as a failed publish", async () => {
  const portal = fakePortal([new Error("socket hang up"), "PUBLISHED"]);
  const clock = fakeClock();

  const result = await waiter(portal, clock);

  // The same discipline the npm confirmation applies: a transport failure says
  // nothing about whether the deployment landed, so it must not be reported as
  // a failed release.
  assert.equal(result.ok, true);
  assert.equal(result.state, "PUBLISHED");
});

test("reports the last transport error when the deadline passes without an answer", async () => {
  const portal = fakePortal(new Error("socket hang up"));
  const clock = fakeClock();

  const result = await waiter(portal, clock, {
    timeoutMs: 6_000,
    intervalMs: 5_000,
  });

  assert.equal(result.ok, false);
  // An unreachable Portal has to read differently from a rejected bundle, or
  // whoever picks up the failed run starts by debugging the wrong thing.
  assert.match(result.reason, /socket hang up/);
});

test("describeFailure names the artifact and reason for each rejected coordinate", () => {
  const message = describeFailure({
    state: "FAILED",
    errors: {
      "io.parity:truapi-host-android:1.0.0": [
        "missing signature",
        "missing javadoc",
      ],
    },
  });

  assert.match(message, /io\.parity:truapi-host-android:1\.0\.0/);
  assert.match(message, /missing signature/);
  assert.match(message, /missing javadoc/);
});

test("describeFailure still says something useful when the Portal sends no errors", () => {
  const message = describeFailure({ state: "VALIDATING", reason: "timed out" });

  assert.match(message, /VALIDATING/);
  assert.match(message, /timed out/);
});
