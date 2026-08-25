/**
 * Confirm that released packages are installable from npm.
 *
 * The release workflow publishes by dispatching to another repository, which
 * reports nothing back, so the registry is the only proof that a version
 * landed. `waitForPublishedVersions` is that proof, and release.yml runs it
 * before creating any tag or GitHub Release.
 *
 * Consumed by `scripts/wait-for-npm-publish.mjs`; unit-tested in
 * `npm-registry.test.mjs` by injecting `fetchStatus` and `sleep`.
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
      return { name, path, version, tag };
    });
}

/**
 * Poll the registry until every package's version is published, or until the
 * attempt budget runs out.
 *
 * Returns the confirmed packages in `published` even when `ok` is false: the
 * publisher tolerates a partial publish, and release.yml drops anything
 * already on npm from a later run, so a package that did publish has to be
 * tagged by this run or it never will be.
 */
export async function waitForPublishedVersions({
  packages,
  fetchStatus,
  sleep,
  timeoutMs,
  intervalMs,
}) {
  // Attempts are counted rather than timed so the tests need no real clock.
  const attempts = Math.max(1, Math.ceil(timeoutMs / intervalMs));
  const confirmed = new Set();

  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    for (const entry of packages) {
      if (confirmed.has(entry.tag)) continue;
      if (await isPublished(fetchStatus, entry)) confirmed.add(entry.tag);
    }

    if (confirmed.size === packages.length) break;
    if (attempt < attempts) await sleep(intervalMs);
  }

  return {
    ok: confirmed.size === packages.length,
    published: packages.filter((entry) => confirmed.has(entry.tag)),
    missing: packages.filter((entry) => !confirmed.has(entry.tag)),
  };
}

async function isPublished(fetchStatus, { name, version }) {
  try {
    return (await fetchStatus(name, version)) === 200;
  } catch {
    // A dropped connection or a 5xx means "unknown", which is not "published".
    return false;
  }
}
