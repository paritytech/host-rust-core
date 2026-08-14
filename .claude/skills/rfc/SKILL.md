---
name: rfc
description: Write, revise, or review an RFC in docs/rfcs/ — interview the author, draft the sections, check the shape. Use for "write an RFC", "draft an RFC", "turn these notes into an RFC", "review this RFC", a bare RFC number, or edits under docs/rfcs/. Not for design docs in docs/design/, PRDs, or issue drafts.
argument-hint: [topic, notes path, or RFC number]
allowed-tools: Read, Grep, Glob, Bash(deno run --allow-read=. -c ${CLAUDE_PROJECT_DIR}/.claude/skills/rfc/deno.json ${CLAUDE_PROJECT_DIR}/.claude/skills/rfc/scripts/check-rfc.ts *), Bash(deno test --allow-read=. -c ${CLAUDE_PROJECT_DIR}/.claude/skills/rfc/deno.json ${CLAUDE_PROJECT_DIR}/.claude/skills/rfc/scripts/check-rfc.test.ts *)
---

# RFC

RFCs live in this repo at `docs/rfcs/NNNN-kebab-title.md`, are listed in `docs/rfcs/_index.md`, and follow `docs/rfcs/0001-template.md`. Read the template and a nearby RFC of similar size before drafting — `0008-statement-store.md` for a compact interface change, `0026-supported-chains.md` for a new method with a rationale-heavy Motivation.

`$ARGUMENTS` is the topic, a path to notes, or the number of an existing RFC to revise.

This skill covers writing the document. Getting it merged, its status, and its rollout are not its business.

## Workflow

1. **Read every input before asking anything** — the user's notes, the design doc or PRD, the RFC being amended, the tracking issue, and the code the change lands in. An RFC that contradicts the code it changes dies on the first review pass.

2. **Interview until nothing is hand-wavy.** Numbered batches of 5–8 questions, grouped by area, as many rounds as it takes; question bank in `references/interview-questions.md`. Skip what the notes already answer, quote the note you are asking about, and name any contradiction you found instead of quietly picking a side. Do not start drafting while a mechanism is still "somehow" — vague design is what reviewers reject, and it always traces to a question nobody asked.

3. **Allocate the number**: highest in `docs/rfcs/_index.md` plus one. Gaps stay unused; they belong to RFCs in sibling repos.

4. **Draft into the repo shape.** Per-section contract, and the rule for leaving a section out rather than padding it, in `references/section-contract.md`. Uppercase MUST/SHOULD/MAY carry RFC 2119 meanings and belong only in `## Detailed Design`: `references/normative-language.md`.

5. **Add the `_index.md` row** in the same change: number, linked title, status, author, PR cell (`—` when there is no PR yet). An RFC missing from the index is invisible to everyone who looks for it.

6. **Gate, then self-review.** Run the checker below, fix what it names, then walk `references/review-rubric.md`.

7. **Revise by patch.** Once the draft exists, edit the sections a comment touches. Never regenerate the file — RFC text is negotiated line by line, and a rewrite silently drops wording that was already settled.

## Gate

```bash
deno run --allow-read=. -c ${CLAUDE_PROJECT_DIR}/.claude/skills/rfc/deno.json ${CLAUDE_PROJECT_DIR}/.claude/skills/rfc/scripts/check-rfc.ts docs/rfcs/0027-your-rfc.md
```

Checks filename, frontmatter (`title`, `owner`), H1 number against filename, required sections, headings with nothing under them, surviving template text, `TODO`/`TBD` markers, RFC 2119 keywords in descriptive sections, and the `_index.md` row. `ERROR` blocks handing the draft back; a `WARN` needs a reason, not a fix.

Passing paths checks one RFC. Passing none audits all 16 — that run reports existing corpus drift, which is not yours to fix unless asked.

The checks are pinned by fixtures — `deno test --allow-read=. -c ${CLAUDE_PROJECT_DIR}/.claude/skills/rfc/deno.json ${CLAUDE_PROJECT_DIR}/.claude/skills/rfc/scripts/check-rfc.test.ts` proves each one fires on a broken fixture and stays silent on two valid RFCs written in deliberately different styles. Change a check, extend the matrix in the same commit.

## Traps

**Attribution.** `owner` is the RFC's author — the person whose proposal this is. Take it from the user, or from `git config user.name` when they say it is theirs, and ask when neither is certain. Never carry a name over from the template or a neighbouring RFC: a wrong-but-plausible owner reads fine to everyone except the person it names.

**Two shapes in one directory.** The repo shape is `Summary / Motivation / Detailed Design / Drawbacks / Alternatives / Unresolved Questions`. Four files in `docs/rfcs/` instead carry `## Explanation`, `## Stakeholders`, and `## Prior Art and References`, copied from the Polkadot Fellowship's template by an earlier version of this skill. Follow the repo template; the gate errors on a missing `## Detailed Design`.

**Facts you cannot source.** A wire id, error variant, type name, threshold, or chain name that you did not read out of the code or hear from the author does not go in the draft. Ask, or put it under `## Unresolved Questions`. Everything an RFC asserts, an implementer will build.

**Length is not thoroughness.** The corpus runs 2 KB to 37 KB and the short ones are not the weak ones — `0021-payment-topup-coins.md` adds one enum variant in 2 KB and says everything it needs to. Match the document to the change.

## References

| Decision | File |
| --- | --- |
| What must I ask before drafting? | `references/interview-questions.md` |
| What goes in each section, and which ones do I leave out? | `references/section-contract.md` |
| MUST, must, or should? | `references/normative-language.md` |
| Is the draft ready to hand back? | `references/review-rubric.md` |
