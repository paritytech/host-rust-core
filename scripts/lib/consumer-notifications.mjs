/**
 * Decide which downstream repositories hear about a TrUAPI release, and what
 * the issue opened on each of them says.
 *
 * `.github/consumers.json` maps a package to the repositories that consume it,
 * so subscribing a repository to another package is one entry in a list. A
 * release commit can publish several packages at once, so each repository gets
 * one combined issue. An earlier notification is only closed once the new one
 * covers every package it named, which keeps a package that was never bumped
 * from disappearing off the board.
 *
 * `announceRelease` drives one repository through that decision against an
 * injected `request`, so `scripts/notify-consumers.mjs` is left owning only
 * transport and logging and every rule here is unit-tested in
 * `consumer-notifications.test.mjs`.
 *
 * Note that the issue listing GitHub serves is a read replica and trails a
 * write by a few seconds, while a read by issue number is authoritative. That
 * is why nothing is closed on the strength of the listing alone.
 */

const MARKER_PREFIX = "truapi-release:";
const LABEL = "truapi-release";

/**
 * Announce a release to one repository: open the combined issue, then retire the
 * notifications it fully covers.
 *
 * `request(method, path, { query, body })` performs one GitHub API call and
 * throws an error carrying `status` on a non-2xx response.
 */
export async function announceRelease({
  request,
  repo,
  packages,
  sourceRepo,
  runUrl,
}) {
  await ensureLabel(request, repo);

  const listed = await request("GET", `/repos/${repo}/issues`, {
    query: { state: "open", labels: LABEL, per_page: "100" },
  });
  const { duplicate, supersede } = selectExistingIssues({
    issues: listed,
    packages,
  });
  if (duplicate !== null) {
    return {
      created: null,
      title: null,
      duplicate: duplicate.number,
      superseded: [],
      skipped: [],
    };
  }

  const { title, body } = renderIssue({ packages, sourceRepo, runUrl });
  const created = await request("POST", `/repos/${repo}/issues`, {
    body: { title, body, labels: [LABEL] },
  });

  const superseded = [];
  const skipped = [];
  for (const issue of supersede) {
    // The listing above is a replica read and can still show an issue that an
    // earlier run closed. A read by number is authoritative, so it is what
    // decides whether there is anything left to close.
    const current = await request(
      "GET",
      `/repos/${repo}/issues/${issue.number}`,
    );
    if (current.state !== "open") {
      skipped.push(issue.number);
      continue;
    }
    await request("POST", `/repos/${repo}/issues/${issue.number}/comments`, {
      body: { body: `Superseded by #${created.number}.` },
    });
    await request("PATCH", `/repos/${repo}/issues/${issue.number}`, {
      body: { state: "closed", state_reason: "not_planned" },
    });
    superseded.push(issue.number);
  }

  return {
    created: created.number,
    title,
    duplicate: null,
    superseded,
    skipped,
  };
}

/** Issues can only carry the label once the repository defines it. */
async function ensureLabel(request, repo) {
  try {
    await request("GET", `/repos/${repo}/labels/${LABEL}`);
  } catch (error) {
    if (error.status !== 404) {
      throw error;
    }
    await request("POST", `/repos/${repo}/labels`, {
      body: {
        name: LABEL,
        color: "e6007a",
        description: "Automated notification of a new TrUAPI release",
      },
    });
  }
}

/**
 * Read and validate `.github/consumers.json`, which maps each published
 * package to the repositories that consume it.
 */
export function parseSubscribers(text) {
  const subscribers = JSON.parse(text);
  if (
    subscribers === null ||
    typeof subscribers !== "object" ||
    Array.isArray(subscribers)
  ) {
    throw new Error(
      "consumers config must be an object mapping a package to its repositories",
    );
  }
  for (const [name, repos] of Object.entries(subscribers)) {
    // An empty list is how a package with no consumer yet is declared.
    if (!Array.isArray(repos)) {
      throw new Error(`${name} must map to a list of repositories`);
    }
    for (const repo of repos) {
      if (typeof repo !== "string" || !/^[^/\s]+\/[^/\s]+$/.test(repo)) {
        throw new Error(
          `${name}: consumer repo must be "owner/name": ${JSON.stringify(repo)}`,
        );
      }
      if (repos.indexOf(repo) !== repos.lastIndexOf(repo)) {
        throw new Error(`${name}: ${repo} is listed twice`);
      }
    }
  }
  return subscribers;
}

/**
 * Group the release by repository, so each one hears about every package it
 * consumes in a single notification.
 */
export function routeNotifications({ packages, subscribers }) {
  const byRepo = new Map();
  for (const released of packages) {
    for (const repo of subscribers[released.name] ?? []) {
      byRepo.set(repo, [...(byRepo.get(repo) ?? []), released]);
    }
  }
  return [...byRepo].map(([repo, packages]) => ({ repo, packages }));
}

/**
 * Published packages the config does not mention at all. The config lists every
 * release target, an unsubscribed one with an empty list, so a missing name is a
 * new target nobody wired up rather than a deliberate silence.
 */
export function unlistedPackages({ packages, subscribers }) {
  return packages
    .map(({ name }) => name)
    .filter((name) => !Object.hasOwn(subscribers, name));
}

/** The title and body of the issue announcing `packages`. */
export function renderIssue({ packages, sourceRepo, runUrl }) {
  const bumps = packages.map(({ name, version }) => `${name} to ${version}`);
  const title = `Bump ${listSentence(bumps)}`;

  const rows = packages.map(({ name, version, tag }) => {
    const notes = `https://github.com/${sourceRepo}/releases/tag/${encodeURIComponent(
      tag ?? `${name}@${version}`,
    )}`;
    return `| \`${name}\` | ${version} | [release notes](${notes}) |`;
  });
  const install = packages
    .map(({ name, version }) => `${name}@${version}`)
    .join(" ");
  const markerBody = packages
    .map(({ name, version }) => `${name}@${version}`)
    .join(" ");

  const body = [
    "A new TrUAPI release is available.",
    "",
    "| Package | Version | Release |",
    "| --- | --- | --- |",
    ...rows,
    "",
    "```",
    `npm install ${install}`,
    "```",
    "",
    `Opened automatically by the [TrUAPI release workflow](${runUrl}). Close this issue once the bump has landed.`,
    "",
    `<!-- ${MARKER_PREFIX} ${markerBody} -->`,
  ].join("\n");

  return { title, body };
}

/**
 * The packages an earlier notification issue announced, or null when the body
 * carries no marker and the issue is therefore somebody else's.
 */
export function parseMarker(body) {
  const match = /<!--\s*truapi-release:\s*([^>]*?)\s*-->/.exec(body ?? "");
  if (match === null) {
    return null;
  }
  return match[1]
    .split(/\s+/)
    .filter((entry) => entry.length > 0)
    .map((entry) => {
      const at = entry.lastIndexOf("@");
      return { name: entry.slice(0, at), version: entry.slice(at + 1) };
    });
}

/**
 * Order two versions, ignoring build metadata. A prerelease sorts below the
 * release it leads to, so `1.0.0-rc.1` never supersedes `1.0.0`.
 */
export function compareVersions(left, right) {
  const split = (version) => {
    const [core, prerelease = ""] = version.split("+")[0].split("-", 2);
    return { core: core.split(".").map(Number), prerelease };
  };
  const a = split(left);
  const b = split(right);

  for (
    let index = 0;
    index < Math.max(a.core.length, b.core.length);
    index += 1
  ) {
    const difference = (a.core[index] ?? 0) - (b.core[index] ?? 0);
    if (difference !== 0) {
      return Math.sign(difference);
    }
  }
  if (a.prerelease === b.prerelease) {
    return 0;
  }
  if (a.prerelease === "") {
    return 1;
  }
  if (b.prerelease === "") {
    return -1;
  }
  return a.prerelease < b.prerelease ? -1 : 1;
}

/**
 * Split the repository's open notification issues into the one that already
 * announces this exact release, if any, and those the new issue fully covers.
 */
export function selectExistingIssues({ issues, packages }) {
  const released = new Map(
    packages.map(({ name, version }) => [name, version]),
  );
  let duplicate = null;
  const supersede = [];

  for (const issue of issues) {
    const announced = parseMarker(issue.body);
    if (announced === null || announced.length === 0) {
      continue;
    }
    const covered = announced.map((entry) => {
      const version = released.get(entry.name);
      return version === undefined
        ? null
        : compareVersions(version, entry.version);
    });
    if (covered.some((order) => order === null || order < 0)) {
      continue;
    }
    if (
      covered.every((order) => order === 0) &&
      announced.length === released.size
    ) {
      duplicate = issue;
    } else {
      supersede.push(issue);
    }
  }

  return { duplicate, supersede };
}

/** "a", "a and b", "a, b and c". */
function listSentence(items) {
  if (items.length < 2) {
    return items.join("");
  }
  return `${items.slice(0, -1).join(", ")} and ${items.at(-1)}`;
}
