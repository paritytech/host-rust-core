/**
 * Fixture matrix for the RFC gate: every check must FIRE on a fixture that
 * breaks it and stay SILENT on two differently-worded valid RFCs.
 *
 *   deno test --allow-read=. -c .claude/skills/rfc/deno.json \
 *     .claude/skills/rfc/scripts/check-rfc.test.ts
 */
import { assert, assertEquals } from "@std/assert";
import { checkRfc, type Finding } from "./check-rfc.ts";

const PATH = "docs/rfcs/0027-payment-quote.md";
const REGISTERED = new Set([27]);

const ids = (f: Finding[]) => f.map((x) => x.id);
const errors = (f: Finding[]) => f.filter((x) => x.level === "ERROR").map((x) => x.id);
const check = (text: string, index: Set<number> | undefined = REGISTERED, path = PATH) =>
  checkRfc(path, text, index);

/** Known-good: em-dash title, flat sections, code in Detailed Design. */
const GOOD_A = `---
title: "Payment Host API v2"
owner: "@somehandle"
---

# RFC 0027 — Payment Host API v2

## Summary

One method is added to the \`Payment\` trait so a product can quote a top-up before it commits to one.

## Motivation

Products today discover the fee only after submitting, so a user sees a cost they never agreed to.

## Detailed Design

The request carries the source and the amount; the host MUST reject a quote whose amount is zero.

\`\`\`rust
#[wire(request_id = 200)]
async fn quote_top_up(&self, _cx: &CallContext, _request: QuoteRequest)
    -> Result<QuoteResponse, CallError<QuoteError>>;
\`\`\`

## Drawbacks

- One more round trip before a top-up.

## Alternatives

Returning the quote inside the existing submit response was rejected: the product needs it before committing.

## Unresolved Questions

Whether the quote should carry a validity window.
`;

/** Known-good, deliberately unlike GOOD_A: colon title, metadata table, nested subsections. */
const GOOD_B = `---
title: "Statement store topic filters"
owner: "@someone-else"
type: rfc
status: draft
pr:
---

# RFC-0027: Statement store topic filters

|                 |                                          |
| --------------- | ---------------------------------------- |
| **Start Date**  | 2026-08-14                               |
| **Description** | OR semantics for statement-store topics. |
| **Authors**     | Someone Else                             |

## Summary

Subscriptions gain OR semantics over topics, which today only match on every listed topic at once.

## Motivation

A product watching four channels opens four subscriptions, and each one costs a connection the host pays for.

## Detailed Design

### Wire shape

\`\`\`rust
enum TopicFilter { MatchAll(Vec<Topic>), MatchAny(Vec<Topic>) }
\`\`\`

### Delivery order

Historical pages arrive before live pages, and the boundary is explicit.

## Drawbacks

Hosts carry a second filter path.

## Alternatives

Client-side fan-in was rejected because the connection cost is what this removes.

## Unresolved Questions

Whether the topic cap belongs in the protocol rather than the host.
`;

function mutate(source: string, from: string | RegExp, to: string): string {
  const out = source.replace(from, to);
  assert(out !== source, `fixture mutation did not apply: ${from}`);
  return out;
}

Deno.test("known-good RFCs raise nothing", () => {
  for (const [label, text] of [["GOOD_A", GOOD_A], ["GOOD_B", GOOD_B]] as const) {
    const f = check(text);
    assertEquals(f, [], `${label} should be clean, got ${JSON.stringify(ids(f))}`);
  }
});

Deno.test("NAME fires on a filename that is not NNNN-kebab-title.md", () => {
  assert(errors(check(GOOD_A, REGISTERED, "docs/rfcs/payment-quote.md")).includes("NAME"));
  assert(errors(check(GOOD_A, REGISTERED, "docs/rfcs/27-payment-quote.md")).includes("NAME"));
  assert(errors(check(GOOD_A, REGISTERED, "docs/rfcs/0027-Payment_Quote.md")).includes("NAME"));
});

Deno.test("FM fires on missing frontmatter and on an empty owner", () => {
  assert(errors(check(GOOD_A.slice(GOOD_A.indexOf("\n# RFC")))).includes("FM"));
  assert(errors(check(mutate(GOOD_A, 'owner: "@somehandle"', 'owner: ""'))).includes("FM"));
});

Deno.test("FMKEY and STATUS warn without blocking", () => {
  const odd = mutate(GOOD_B, "status: draft", "status: in-review\nreviewer: someone");
  const f = check(odd);
  assertEquals(errors(f), []);
  assert(ids(f).includes("STATUS"));
  assert(ids(f).includes("FMKEY"));
});

Deno.test("H1 fires on a number that disagrees with the filename", () => {
  assert(errors(check(mutate(GOOD_A, "# RFC 0027 —", "# RFC 0031 —"))).includes("H1"));
});

Deno.test("H1 fires when the title line is not an RFC heading at all", () => {
  const wrong = mutate(GOOD_A, "# RFC 0027 — Payment Host API v2", "# Payment Host API v2");
  assert(errors(check(wrong)).includes("H1"));
});

Deno.test("H1FORM warns on attested-but-odd title punctuation", () => {
  const f = check(mutate(GOOD_A, "# RFC 0027 —", "# RFC 0027 -"));
  assertEquals(errors(f), []);
  assert(ids(f).includes("H1FORM"));
});

Deno.test("SEC errors on a missing required section", () => {
  const upstreamShape = mutate(GOOD_A, "## Detailed Design", "## Explanation");
  assert(errors(check(upstreamShape)).includes("SEC"));
});

Deno.test("SEC warns on a missing expected section", () => {
  const truncated = GOOD_A.slice(0, GOOD_A.indexOf("## Alternatives"));
  const f = check(truncated);
  assert(f.some((x) => x.id === "SEC" && x.level === "WARN"));
});

Deno.test("EMPTY fires on a heading with neither prose nor subsections", () => {
  const empty = mutate(GOOD_A, "## Drawbacks\n\n- One more round trip before a top-up.", "## Drawbacks\n");
  assert(errors(check(empty)).includes("EMPTY"));
});

Deno.test("EMPTY stays silent on a parent heading whose children carry the content", () => {
  assertEquals(errors(check(GOOD_B)), []);
});

Deno.test("EMPTY stays silent on a section whose only content is a code fence", () => {
  const fenceOnly = mutate(
    GOOD_A,
    "## Drawbacks\n\n- One more round trip before a top-up.",
    "## Drawbacks\n\n```text\nOne more round trip.\n```",
  );
  assertEquals(errors(check(fenceOnly)), []);
});

Deno.test("PLACEHOLDER fires on surviving template prose and on the template owner handle", () => {
  const lazyProse = mutate(
    GOOD_A,
    "Products today discover the fee only after submitting, so a user sees a cost they never agreed to.",
    "Why are we doing this? What problem does it solve?",
  );
  assert(errors(check(lazyProse)).includes("PLACEHOLDER"));

  const lazyOwner = mutate(GOOD_A, 'owner: "@somehandle"', 'owner: "@ownerhandle"');
  assert(errors(check(lazyOwner)).includes("PLACEHOLDER"));
});

Deno.test("MARKER fires on TODO in prose but not inside a code fence", () => {
  const inProse = mutate(GOOD_A, "## Unresolved Questions\n", "## Unresolved Questions\n\nTODO\n");
  assert(errors(check(inProse)).includes("MARKER"));

  const inCode = mutate(
    GOOD_A,
    "#[wire(request_id = 200)]",
    "// TODO(host): widen later\n#[wire(request_id = 200)]",
  );
  assertEquals(errors(check(inCode)), []);
});

Deno.test("CODE warns when no fenced block states the interface", () => {
  const noCode = GOOD_A.replace(/```rust[\s\S]*?```\n/, "");
  assert(ids(check(noCode)).includes("CODE"));
});

Deno.test("KEYWORD warns for an RFC 2119 keyword in a descriptive section only", () => {
  const inDrawbacks = mutate(
    GOOD_A,
    "- One more round trip before a top-up.",
    "- Products MUST NOT cache the quote.",
  );
  const f = check(inDrawbacks);
  assertEquals(errors(f), []);
  assert(ids(f).includes("KEYWORD"));

  // GOOD_A already says "the host MUST reject" under Detailed Design; that is the normative home.
  assert(!ids(check(GOOD_A)).includes("KEYWORD"));
});

Deno.test("INDEX fires when the number has no row, and is skipped when the index is unreadable", () => {
  assert(errors(check(GOOD_A, new Set([26]))).includes("INDEX"));
  assertEquals(errors(check(GOOD_A, undefined)), []);
});
