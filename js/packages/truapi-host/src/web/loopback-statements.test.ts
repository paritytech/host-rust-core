import { describe, expect, it } from "bun:test";
import { SignedStatement } from "@parity/truapi";
import { createLoopbackStatements } from "./loopback-statements.js";

const TOPIC_A = `0x${"aa".repeat(32)}`;
const TOPIC_B = `0x${"bb".repeat(32)}`;

/** A statement carrying `topics`, encoded the way the core sends it. */
function statement(topics: string[]): string {
  const bytes = SignedStatement.enc({
    proof: { tag: "Sr25519", value: { signature: `0x${"09".repeat(64)}`, signer: `0x${"08".repeat(32)}` } },
    decryptionKey: undefined,
    expiry: undefined,
    channel: undefined,
    topics: topics as never,
    data: undefined,
  } as never);
  return `0x${Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")}`;
}

function subscribe(store: ReturnType<typeof createLoopbackStatements>, filter: unknown) {
  const frames: string[] = [];
  const respond = (frame: string) => frames.push(frame);
  store.handle(
    JSON.stringify({ jsonrpc: "2.0", id: "s1", method: "statement_subscribeStatement", params: [filter] }),
    respond,
  );
  return { frames, respond };
}

function delivered(frames: string[]) {
  return frames.filter((f) => f.includes("newStatements")).length;
}

describe("the in-page statement store", () => {
  it("accepts a submission, because the core rejects anything but new/known", () => {
    const store = createLoopbackStatements();
    const replies: string[] = [];
    const handled = store.handle(
      JSON.stringify({ jsonrpc: "2.0", id: 1, method: "statement_submit", params: [statement([])] }),
      (f) => replies.push(f),
    );
    expect(handled).toBe(true);
    // A bare "new" string is refused by the core as `not accepted`; it reads
    // `.status` off an object.
    expect(JSON.parse(replies[0]!).result).toEqual({ status: "new" });
  });

  it("delivers a submission to a subscriber watching its topic", () => {
    const store = createLoopbackStatements();
    const { frames, respond } = subscribe(store, { matchAll: [TOPIC_A] });
    store.handle(
      JSON.stringify({ id: 2, method: "statement_submit", params: [statement([TOPIC_A])] }),
      respond,
    );
    expect(delivered(frames)).toBe(1);
  });

  it("does not deliver to a subscriber watching a different topic", () => {
    // Without this, a store that fans out to everyone would look correct.
    const store = createLoopbackStatements();
    const { frames, respond } = subscribe(store, { matchAll: [TOPIC_B] });
    store.handle(
      JSON.stringify({ id: 3, method: "statement_submit", params: [statement([TOPIC_A])] }),
      respond,
    );
    expect(delivered(frames)).toBe(0);
  });

  it("matchAny needs one topic where matchAll needs them all", () => {
    const store = createLoopbackStatements();
    const any = subscribe(store, { matchAny: [TOPIC_A, TOPIC_B] });
    const all = subscribe(store, { matchAll: [TOPIC_A, TOPIC_B] });
    store.handle(
      JSON.stringify({ id: 4, method: "statement_submit", params: [statement([TOPIC_A])] }),
      any.respond,
    );
    expect(delivered(any.frames)).toBe(1);
    expect(delivered(all.frames)).toBe(0);
  });

  it("stops delivering after unsubscribe", () => {
    const store = createLoopbackStatements();
    const { frames, respond } = subscribe(store, { matchAll: [] });
    const id = JSON.parse(frames[0]!).result as string;
    store.handle(
      JSON.stringify({ id: 5, method: "statement_unsubscribeStatement", params: [id] }),
      respond,
    );
    store.handle(
      JSON.stringify({ id: 6, method: "statement_submit", params: [statement([TOPIC_A])] }),
      respond,
    );
    expect(delivered(frames)).toBe(0);
  });

  it("leaves everything else to the caller", () => {
    const store = createLoopbackStatements();
    // A chain read must still reach the chain, or serving statements locally
    // would silently blind every other call on that connection.
    expect(
      store.handle(
        JSON.stringify({ id: 7, method: "state_getStorage", params: ["0x00"] }),
        () => {},
      ),
    ).toBe(false);
  });

  it("records submissions and forgets them on clear", () => {
    const store = createLoopbackStatements();
    const encoded = statement([TOPIC_A]);
    store.handle(
      JSON.stringify({ id: 8, method: "statement_submit", params: [encoded] }),
      () => {},
    );
    expect(store.submitted()).toEqual([encoded]);
    store.clear();
    expect(store.submitted()).toEqual([]);
  });

  it("does not count an injection as a submission", () => {
    // `submitted()` is how a suite sees what the product sent. Counting an
    // injection there lets a test assert the product submitted something while
    // the host was the only one that acted.
    const store = createLoopbackStatements();
    const { frames } = subscribe(store, null);
    const afterSubscribe = frames.length;
    store.inject(statement([TOPIC_A]));

    expect(store.submitted()).toEqual([]);
    // Still delivered, so this is about the record and not a dropped statement.
    expect(frames.length).toBe(afterSubscribe + 1);
  });
});
