/**
 * Confirm that released packages are installable from npm.
 *
 * The release workflow publishes by dispatching to another repository, which
 * reports nothing back, so the registry is the only proof that a version
 * landed. `waitForPublishedVersions` is that proof, and release.yml runs it
 * before creating any tag or GitHub Release.
 *
 * Consumed by `scripts/wait-for-npm-publish.mjs`; unit-tested in
 * `npm-registry.test.mjs` by injecting `fetchStatus`, `sleep` and `now`.
 */

const FIELD_COUNT = 4;

/**
 * Parse the `name|path|version|tag` block that release.yml's version step
 * emits as `steps.version.outputs.packages`.
 */
export function parsePackageLines(text) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => {
      const fields = line.split("|");
      if (fields.length !== FIELD_COUNT) {
        throw new Error(
          `expected four fields (name|path|version|tag), got ${fields.length}: ${line}`,
        );
      }
      const [name, path, version, tag] = fields;
      // A blank version addresses the package document, which answers 200.
      if (name === "" || version === "") {
        throw new Error(`name and version must not be blank: ${line}`);
      }
      return { name, path, version, tag };
    });
}

/** Packages from `--package` and `--version`, or from the block on stdin. */
export function resolvePackages({ args, readInput }) {
  const flag = (flagName) => {
    const at = args.indexOf(`--${flagName}`);
    return at === -1 ? undefined : args[at + 1];
  };
  const name = flag("package");
  const version = flag("version");

  if (name === undefined && version === undefined) {
    return parsePackageLines(readInput());
  }
  if (name === undefined || version === undefined) {
    throw new Error("--package and --version must be given together");
  }
  // No path: only release.yml's tagging steps read that field.
  return parsePackageLines(`${name}||${version}|${name}@${version}`);
}

/**
 * Poll the registry until every package's version is published, or until the
 * deadline passes.
 *
 * Returns the confirmed packages in `published` even when `ok` is false: the
 * publisher tolerates a partial publish, and release.yml drops anything
 * already on npm from a later run, so a package that did publish has to be
 * tagged by this run or it never will be.
 *
 * `errors` carries the last failure per package, so an unreachable registry
 * reads differently from an absent version. The deadline bounds when a round
 * starts, not when it ends, so callers bound each request.
 */
export async function waitForPublishedVersions({
  packages,
  fetchStatus,
  sleep,
  timeoutMs,
  intervalMs,
  now = Date.now,
}) {
  const deadline = now() + timeoutMs;
  const confirmed = new Set();
  const errors = new Map();

  for (;;) {
    for (const entry of packages) {
      if (confirmed.has(entry.tag)) continue;
      if (await isPublished(fetchStatus, entry, errors))
        confirmed.add(entry.tag);
    }

    if (confirmed.size === packages.length) break;
    // Never sleep past the deadline; the caller's timeout is only a backstop.
    if (now() + intervalMs >= deadline) break;
    await sleep(intervalMs);
  }

  return {
    ok: confirmed.size === packages.length,
    published: packages.filter((entry) => confirmed.has(entry.tag)),
    missing: packages.filter((entry) => !confirmed.has(entry.tag)),
    errors,
  };
}

/**
 * Write the confirmed subset, then report what is missing, then return the exit
 * code. The order is load-bearing: a partial publish must still be tagged.
 */
export function reportConfirmation({ result, writeOutput, logError }) {
  writeOutput(result.published);

  for (const entry of result.missing) {
    const reason = result.errors?.get(entry.tag);
    logError(
      reason
        ? `${entry.tag} could not be confirmed on npm: ${reason}`
        : `${entry.tag} is not on npm; the publish did not land.`,
    );
  }

  return result.ok ? 0 : 1;
}

async function isPublished(fetchStatus, entry, errors) {
  try {
    const status = await fetchStatus(entry.name, entry.version);
    if (status === 200) {
      errors.delete(entry.tag);
      return true;
    }
    if (status !== 404) errors.set(entry.tag, `registry answered ${status}`);
    return false;
  } catch (error) {
    errors.set(entry.tag, error.message);
    return false;
  }
}
