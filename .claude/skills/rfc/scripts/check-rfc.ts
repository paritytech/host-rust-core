#!/usr/bin/env -S deno run --allow-read=.
/**
 * Structural gate for RFCs in `docs/rfcs/`.
 *
 * Checks the shape `docs/rfcs/0001-template.md` and the existing corpus use:
 * filename, frontmatter, H1, required sections, empty headings, surviving
 * template prose, unresolved markers, RFC 2119 keywords in descriptive
 * sections, and registration in `docs/rfcs/_index.md`.
 *
 *   deno run --allow-read=. -c .claude/skills/rfc/deno.json \
 *     .claude/skills/rfc/scripts/check-rfc.ts [paths...]
 *
 * No paths: every numbered RFC under `docs/rfcs/`.
 * Exit 1 when any ERROR fired.
 */
import { parseArgs } from "@std/cli/parse-args";
import { expandGlob } from "@std/fs/expand-glob";
import { basename, relative } from "@std/path";
import { bold, red, yellow } from "@std/fmt/colors";
import { extract } from "@std/front-matter/yaml";
import { test as hasFrontMatter } from "@std/front-matter/test";

export type Finding = { id: string; level: "ERROR" | "WARN"; message: string };

const INDEX = "docs/rfcs/_index.md";

/** Sentences from docs/rfcs/0001-template.md that must not survive into a real RFC. */
const PLACEHOLDERS = [
  "One-paragraph explanation of the proposal.",
  "Why are we doing this?",
  "What problem does it solve? What use cases does it support?",
  "Explain the design in enough detail that someone familiar with the codebase",
  "Why should we _not_ do this?",
  "What other designs were considered?",
  "What parts of the design are still open?",
  "RFC Title",
  "@ownerhandle",
];

const MARKER = /\b(TODO|TBD|FIXME|XXX)\b|\bLorem ipsum\b/;

/** Both attested in docs/rfcs: "RFC 0022 — Title" (8 files) and "RFC-0010: Title" (6). */
const H1 = /^RFC[ -]0*(\d+)\s*(?:—|-|:)\s*\S/;
const H1_CANONICAL = /^(?:RFC \d{4} — |RFC-\d{4}: )\S/;
const H1_HINT = `RFC 0027 — Title" or "# RFC-0027: Title`;

const REQUIRED = ["Summary", "Motivation", "Detailed Design"];
const EXPECTED = ["Drawbacks", "Alternatives", "Unresolved Questions"];
const NORMATIVE_SECTION = "Detailed Design";

/** Sections that describe rather than specify; an uppercase RFC 2119 keyword here is prose. */
const NON_NORMATIVE = [
  "Summary",
  "Motivation",
  "Drawbacks",
  "Alternatives",
  "Unresolved Questions",
  "Non-goals",
  "Out of Scope",
];

const KNOWN_FM_KEYS = ["title", "owner", "author", "type", "status", "pr", "breaking", "created"];
const KNOWN_STATUS = ["draft", "accepted", "rejected", "superseded"];

const FENCE = /^```[\s\S]*?^```[^\n]*$/gm;

type Section = {
  heading: string;
  depth: number;
  /** Everything under the heading, code fences included. */
  content: string;
  /** Same span with fenced blocks removed, for prose-level checks. */
  prose: string;
  hasChildren: boolean;
};

/**
 * Split the body at ATX headings. `hasChildren` is true when a deeper heading
 * follows before the next same-or-shallower one, so a parent that only
 * introduces subsections is not mistaken for an empty section.
 */
function sections(body: string): Section[] {
  const out: Section[] = [];
  let inFence = false;
  for (const line of body.split("\n")) {
    if (line.startsWith("```")) inFence = !inFence;
    const h = inFence ? null : /^(#{2,6})\s+(.*\S)\s*$/.exec(line);
    if (!h) {
      if (out.length) out[out.length - 1].content += line + "\n";
      continue;
    }
    const depth = h[1].length;
    for (let i = out.length - 1; i >= 0; i--) {
      if (out[i].depth < depth) {
        out[i].hasChildren = true;
        break;
      }
    }
    out.push({ heading: h[2], depth, content: "", prose: "", hasChildren: false });
  }
  for (const s of out) s.prose = s.content.replace(FENCE, "");
  return out;
}

export function checkRfc(path: string, text: string, indexNumbers?: Set<number>): Finding[] {
  const f: Finding[] = [];
  const err = (id: string, message: string) => f.push({ id, level: "ERROR", message });
  const warn = (id: string, message: string) => f.push({ id, level: "WARN", message });

  const fileNumber = /^(\d{4})-[a-z0-9]+(?:-[a-z0-9]+)*\.md$/.exec(basename(path));
  if (!fileNumber) err("NAME", `filename is not NNNN-kebab-title.md: ${basename(path)}`);

  const { attrs, body } = hasFrontMatter(text)
    ? extract<Record<string, unknown>>(text)
    : { attrs: {} as Record<string, unknown>, body: text };

  if (!hasFrontMatter(text)) {
    err("FM", "no YAML frontmatter; needs title and owner");
  } else {
    for (const key of ["title", "owner"]) {
      if (!String(attrs[key] ?? "").trim()) err("FM", `frontmatter ${key} is missing or empty`);
    }
    for (const key of Object.keys(attrs)) {
      if (!KNOWN_FM_KEYS.includes(key)) warn("FMKEY", `unknown frontmatter key: ${key}`);
    }
    const status = String(attrs.status ?? "").trim();
    if (status && !KNOWN_STATUS.includes(status)) {
      warn("STATUS", `status "${status}" is not one of ${KNOWN_STATUS.join(", ")}`);
    }
  }

  const h1 = /^#\s+(.*\S)\s*$/m.exec(body)?.[1];
  if (!h1) {
    err("H1", `no H1 title; expected "# ${H1_HINT}"`);
  } else {
    const m = H1.exec(h1);
    if (!m) err("H1", `H1 is not an RFC title of the form "# ${H1_HINT}": ${h1}`);
    else if (fileNumber && Number(m[1]) !== Number(fileNumber[1])) {
      err("H1", `H1 number ${m[1]} does not match filename number ${fileNumber[1]}`);
    }
    if (m && !H1_CANONICAL.test(h1)) {
      warn("H1FORM", `H1 is accepted but off-canonical; prefer "# ${H1_HINT}"`);
    }
  }

  const secs = sections(body);
  const headings = secs.filter((s) => s.depth === 2).map((s) => s.heading);
  for (const want of REQUIRED) {
    if (!headings.includes(want)) err("SEC", `missing required section: ## ${want}`);
  }
  for (const want of EXPECTED) {
    if (!headings.includes(want)) warn("SEC", `no ## ${want} — omit only if it has nothing to say`);
  }
  for (const s of secs) {
    if (s.content.trim() || s.hasChildren) continue;
    err("EMPTY", `heading with neither prose nor subsections: ${"#".repeat(s.depth)} ${s.heading}`);
  }

  // Frontmatter included: "RFC Title" and "@ownerhandle" are template values.
  const prose = text.replace(FENCE, "");
  for (const placeholder of PLACEHOLDERS) {
    if (prose.includes(placeholder)) {
      err("PLACEHOLDER", `template text survives: "${placeholder.slice(0, 48)}"`);
    }
  }
  const marker = MARKER.exec(prose);
  if (marker) err("MARKER", `unresolved marker in prose: ${marker[0]}`);

  if (!/^```/m.test(body)) {
    warn("CODE", "no fenced code block — an interface change states the exact signature");
  }

  for (const s of secs) {
    if (!NON_NORMATIVE.includes(s.heading)) continue;
    const kw = /\b(MUST NOT|MUST|SHALL NOT|SHALL|SHOULD NOT|SHOULD|REQUIRED|RECOMMENDED)\b/.exec(s.prose);
    if (kw) {
      warn(
        "KEYWORD",
        `RFC 2119 "${kw[0]}" under ## ${s.heading}; requirements belong in ${NORMATIVE_SECTION}`,
      );
    }
  }

  if (indexNumbers && fileNumber && !indexNumbers.has(Number(fileNumber[1]))) {
    err("INDEX", `RFC ${fileNumber[1]} has no row in ${INDEX}`);
  }

  return f;
}

/** Numbers registered in the RFC index, or undefined when it is unreadable. */
async function indexNumbers(): Promise<Set<number> | undefined> {
  try {
    const text = await Deno.readTextFile(INDEX);
    return new Set([...text.matchAll(/^\|\s*(\d{4})\s*\|/gm)].map((m) => Number(m[1])));
  } catch {
    return undefined;
  }
}

if (import.meta.main) {
  const args = parseArgs(Deno.args);
  const paths = args._.map(String);
  if (paths.length === 0) {
    for await (const entry of expandGlob("docs/rfcs/[0-9][0-9][0-9][0-9]-*.md")) {
      if (!entry.name.endsWith("-template.md")) paths.push(relative(Deno.cwd(), entry.path));
    }
    paths.sort();
  }

  const index = await indexNumbers();
  if (!index) console.log(yellow(`WARN  [INDEX] ${INDEX} unreadable — registration unchecked`));

  let errors = 0;
  let warnings = 0;
  const seen = new Map<string, string>();
  for (const path of paths) {
    const findings = checkRfc(path, await Deno.readTextFile(path), index);

    const number = /^(\d{4})-/.exec(basename(path))?.[1];
    if (number) {
      const prior = seen.get(number);
      if (prior) {
        findings.push({ id: "DUP", level: "ERROR", message: `number ${number} also claimed by ${prior}` });
      } else seen.set(number, path);
    }

    if (findings.length) console.log(bold(path));
    for (const { id, level, message } of findings) {
      const line = `  ${level.padEnd(5)} [${id}] ${message}`;
      console.log(level === "ERROR" ? red(line) : yellow(line));
      level === "ERROR" ? errors++ : warnings++;
    }
  }

  console.log(`\n${paths.length} file(s), ${errors} error(s), ${warnings} warning(s)`);
  Deno.exit(errors ? 1 : 0);
}
