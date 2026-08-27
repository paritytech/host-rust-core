---
name: rfc
description: Draft a short RFC for this repo. Use when the user wants to create, draft, or write an RFC.
argument-hint: [topic or brief description]
context: fork
---

# RFC

Write a 1-2 page RFC. It exists to get agreement on an approach, not to specify it:
details are the implementer's call and need no prior approval here.

## Mechanics

- File `docs/rfcs/<kebab-title>.md` from [template.md](template.md). **Do not number it**
  and **do not touch `_index.md`** — `number-rfc.yml` assigns the number on merge to
  `main` and rebuilds the index from the files on disk.
- Keep the H1 as `# RFC — Title`, em dash included; the numbering step rewrites that
  exact form to inject the number.
- Set `status: draft` in the frontmatter. Omitting it makes CI index the RFC as
  `accepted`.
- `check-rfc.yml` fails any PR touching `docs/rfcs/**` that does not also change
  `rust/crates/truapi/`. A host-side proposal cannot satisfy that and belongs in
  `docs/features/` instead.

## Writing it

- Lead with the problem. If it isn't concrete, the RFC isn't ready.
- Describe what changes and why, not signatures, thresholds or edge cases.
- Cut every sentence that would not change a reader's mind.
- Prefer a stated assumption to a blocking question. Ask the author only when the
  answer changes the approach.
- Omit any section you would otherwise fill for the template's sake.

## Before handing it over

Re-read it as a reviewer with ten minutes. Cut what you would skim. Then tell the
author what you cut and what you assumed.
