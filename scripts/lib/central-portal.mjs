/**
 * Confirm that a Central Portal deployment reached the state a release asked
 * for.
 *
 * The upload endpoint answers with a deployment id and nothing else, so the
 * status endpoint is the only proof that a version was accepted — the same
 * reason `npm-registry.mjs` exists for npm. A release publishes with
 * `AUTOMATIC` and waits for `PUBLISHED`; a rehearsal publishes with
 * `USER_MANAGED` and waits for `VALIDATED`, which is where the Portal parks a
 * deployment until a person releases or drops it.
 *
 * Consumed by `scripts/wait-for-central-publish.mjs`; unit-tested in
 * `central-portal.test.mjs` by injecting `fetchState`, `sleep` and `now`.
 */

/**
 * Deployment states in the order the Portal moves through them. Validation and
 * publication are one progression, so a deployment at or past the target
 * satisfies it — an automatic publish can overtake a poll and land on
 * `PUBLISHED` when the caller only asked for `VALIDATED`.
 */
const PROGRESSION = [
  "PENDING",
  "VALIDATING",
  "VALIDATED",
  "PUBLISHING",
  "PUBLISHED",
];

/** Poll one deployment until it reaches `target`, is rejected, or times out. */
export async function waitForDeployment({
  deploymentId,
  fetchState,
  sleep,
  timeoutMs,
  intervalMs,
  target,
  now = Date.now,
}) {
  const wanted = PROGRESSION.indexOf(target);
  if (wanted === -1) throw new Error(`unknown target state: ${target}`);

  const deadline = now() + timeoutMs;
  let state;
  let transportError;

  for (;;) {
    try {
      const status = await fetchState(deploymentId);
      state = status.deploymentState;
      transportError = undefined;

      if (state === "FAILED") {
        return {
          ok: false,
          state,
          errors: status.errors,
          reason: "the Portal rejected the bundle",
        };
      }

      const reached = PROGRESSION.indexOf(state);
      if (reached === -1) {
        return {
          ok: false,
          state,
          reason: `unrecognised deployment state: ${state}`,
        };
      }
      if (reached >= wanted) return { ok: true, state };
    } catch (error) {
      // A status call that never answered says nothing about whether the
      // deployment landed, so it must not be reported as a failed release.
      transportError = error.message;
    }

    // Never sleep past the deadline; the caller's job timeout is a backstop.
    if (now() + intervalMs >= deadline) break;
    await sleep(intervalMs);
  }

  return {
    ok: false,
    state,
    reason:
      transportError === undefined
        ? `still ${state} when the ${timeoutMs}ms deadline passed`
        : `the Portal could not be reached: ${transportError}`,
  };
}

/**
 * One human-readable account of a failed wait. The Portal's own `errors` name
 * which rule the bundle broke, so they belong in the job log rather than
 * flattened into "publish failed".
 */
export function describeFailure({ state, errors, reason }) {
  const head = `deployment ${state ?? "state unknown"}${reason === undefined ? "" : `: ${reason}`}`;
  if (errors === undefined) return head;

  const detail = Object.entries(errors).map(
    ([coordinate, messages]) => `  ${coordinate}: ${[messages].flat().join("; ")}`,
  );
  return [head, ...detail].join("\n");
}
