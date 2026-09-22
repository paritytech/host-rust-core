// An in-page statement store, for suites that exercise a product's
// statement flows without a chain.
//
// The core reaches the statement store over its chain connection, so this is
// where a host can serve one: `statement_submit` is accepted and fanned out to
// the matching subscriptions, and nothing leaves the page. A statement
// accepted here is not registered anywhere, so a real store would refuse what
// this one takes.

import { SignedStatement } from "@parity/truapi";

/** A live `statement_subscribeStatement`, and what it asked for. */
interface Subscription {
  id: string;
  /** Empty topics means everything, for either kind. */
  kind: "MatchAll" | "MatchAny";
  topics: string[];
  notify: (frame: string) => void;
}

/** Statement methods the core sends over the chain connection. */
const SUBMIT = "statement_submit";
const SUBSCRIBE = "statement_subscribeStatement";
const UNSUBSCRIBE = "statement_unsubscribeStatement";

function hex(bytes: Uint8Array): string {
  return `0x${Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")}`;
}

function bytes(value: string): Uint8Array {
  const body = value.startsWith("0x") ? value.slice(2) : value;
  return Uint8Array.from((body.match(/../g) ?? []).map((b) => parseInt(b, 16)));
}

/**
 * Topics of a submitted statement, or `undefined` when it will not decode.
 *
 * An undecodable statement is still delivered, to everything: a suite chasing
 * a missing delivery has something to see, where a silent drop looks like the
 * product never submitted.
 */
function topicsOf(encoded: string): string[] | undefined {
  try {
    return SignedStatement.dec(bytes(encoded)).topics.map((topic) =>
      typeof topic === "string" ? topic.toLowerCase() : hex(topic),
    );
  } catch {
    return undefined;
  }
}

/** Read the filter the core sent, defaulting to "everything". */
function parseFilter(raw: unknown): Pick<Subscription, "kind" | "topics"> {
  const toTopics = (values: unknown[]) =>
    values.map((topic) => String(topic).toLowerCase());
  if (Array.isArray(raw)) return { kind: "MatchAll", topics: toTopics(raw) };
  if (typeof raw !== "object" || raw === null) {
    return { kind: "MatchAll", topics: [] };
  }
  const filter = raw as Record<string, unknown>;
  for (const [key, kind] of [
    ["matchAny", "MatchAny"],
    ["matchAll", "MatchAll"],
  ] as const) {
    if (!(key in filter)) continue;
    const topics = filter[key];
    return { kind, topics: Array.isArray(topics) ? toTopics(topics) : [] };
  }
  // An unreadable filter subscribes to everything: extra deliveries are
  // visible, a black hole is not.
  return { kind: "MatchAll", topics: [] };
}

/** Whether `topics` satisfies what this subscription asked for. */
function matches(subscription: Subscription, topics: string[] | undefined) {
  if (subscription.topics.length === 0 || topics === undefined) return true;
  return subscription.kind === "MatchAll"
    ? subscription.topics.every((topic) => topics.includes(topic))
    : subscription.topics.some((topic) => topics.includes(topic));
}

/** A statement store shared by every connection the host hands out. */
export interface LoopbackStatements {
  /** Handle one request, or return false to leave it to the caller. */
  handle(request: string, respond: (frame: string) => void): boolean;
  /** Forget the subscriptions one connection owns. */
  release(respond: (frame: string) => void): void;
  /** Statements submitted so far, as `0x` hex, in order. */
  submitted(): string[];
  /** Deliver `statement` as if it had been submitted by someone else. */
  inject(statement: string): number;
  /** Drop the record of what was submitted. */
  clear(): void;
}

/** Build the store. One per mock host, shared across its connections. */
export function createLoopbackStatements(): LoopbackStatements {
  const subscriptions = new Set<Subscription>();
  const submissions: string[] = [];
  let nextId = 1;

  const deliver = (encoded: string) => {
    const topics = topicsOf(encoded);
    let delivered = 0;
    for (const subscription of subscriptions) {
      if (!matches(subscription, topics)) continue;
      subscription.notify(
        JSON.stringify({
          jsonrpc: "2.0",
          method: SUBSCRIBE,
          params: {
            subscription: subscription.id,
            result: {
              event: "newStatements",
              data: { statements: [encoded], remaining: 0 },
            },
          },
        }),
      );
      delivered += 1;
    }
    return delivered;
  };

  return {
    handle(request, respond) {
      let frame: { id?: unknown; method?: string; params?: unknown[] };
      try {
        frame = JSON.parse(request) as typeof frame;
      } catch {
        return false;
      }
      const reply = (result: unknown) =>
        respond(JSON.stringify({ jsonrpc: "2.0", id: frame.id, result }));

      switch (frame.method) {
        case SUBMIT: {
          const encoded = String((frame.params ?? [])[0] ?? "");
          submissions.push(encoded);
          // The core accepts only `new`/`known`, and reads `.status` off an
          // object; a bare string is rejected as "not accepted".
          reply({ status: "new" });
          deliver(encoded);
          return true;
        }
        case SUBSCRIBE: {
          const id = `loopback-sub-${nextId++}`;
          subscriptions.add({
            id,
            ...parseFilter((frame.params ?? [])[0]),
            notify: respond,
          });
          reply(id);
          return true;
        }
        case UNSUBSCRIBE: {
          const target = String((frame.params ?? [])[0] ?? "");
          for (const subscription of subscriptions) {
            if (subscription.id === target) subscriptions.delete(subscription);
          }
          reply(true);
          return true;
        }
        default:
          return false;
      }
    },
    release(respond) {
      for (const subscription of subscriptions) {
        if (subscription.notify === respond) subscriptions.delete(subscription);
      }
    },
    submitted: () => [...submissions],
    inject: (statement) => {
      // Not recorded as a submission: `submitted()` is how a suite sees what
      // the product sent, and an injection is the host standing in for someone
      // else. `MockHost.getInjectedStatements` keeps the injection record.
      const encoded = statement.startsWith("0x") ? statement : `0x${statement}`;
      return deliver(encoded);
    },
    clear: () => {
      submissions.length = 0;
    },
  };
}
