import { describe, expect, test } from "bun:test";

import { encodeWireMessage } from "@parity/truapi";
import * as W from "@parity/truapi/wire-table";

import { createDebugIngest, DEFAULT_MAX_ID_CHARS } from "./ingest.js";
import type { DebugFrameEnvelope } from "./ingest.js";
import type { ObservedFrame } from "./observed-frame.js";
import { createMethodNameMap, createWireDebugger } from "./wire-debugger.js";

/** The real generated table, keyed the way `createDebugSession` keys it. */
const METHOD_NAMES = createMethodNameMap(
  W as unknown as Record<string, unknown>,
  ["account", "signing", "chain", "chat", "resourceAllocation"],
);

/** One host-tap envelope carrying `frameId` under correlation id `requestId`. */
function envelope(
  requestId: string,
  frameId: number,
  value = new Uint8Array([0]),
  dir: "in" | "out" = "out",
  channelId = "myapp.dot",
): DebugFrameEnvelope {
  const encoded = encodeWireMessage({ requestId, payload: { id: frameId, value } });
  if (encoded.isErr()) throw encoded.error;
  return { channelId, dir, frame: encoded.value };
}

/** Collect every frame an ingest emits. */
function collect(options: Parameters<typeof createDebugIngest>[1] = {}) {
  const seen: ObservedFrame[] = [];
  return { seen, ingest: createDebugIngest((f) => seen.push(f), options) };
}

describe("ingest resolves role from the wire table", () => {
  test("role is a pure function of frameId, across every leg of a method", () => {
    const { seen, ingest } = collect({ methodNames: METHOD_NAMES });

    // A request/response pair and a subscription's start/receive legs. Each id
    // carries its own role on the wire table; none of them needs correlation
    // state, and they arrive here out of any lifecycle order on purpose.
    ingest(envelope("p:1", W.ACCOUNT_GET_ACCOUNT.response));
    ingest(envelope("p:1", W.ACCOUNT_GET_ACCOUNT.request));
    ingest(envelope("p:2", W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.receive));
    ingest(envelope("p:2", W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.start));

    expect(seen.map((f) => f.role)).toEqual([
      "response",
      "request",
      "receive",
      "start",
    ]);
  });

  test("an off-table id and a map-less ingest both fall back to unknown", () => {
    const withMap = collect({ methodNames: METHOD_NAMES });
    // 250 is above every id the current table assigns.
    withMap.ingest(envelope("p:1", 250));
    expect(withMap.seen[0]?.role).toBe("unknown");

    const withoutMap = collect();
    withoutMap.ingest(envelope("p:1", W.ACCOUNT_GET_ACCOUNT.request));
    expect(withoutMap.seen[0]?.role).toBe("unknown");
  });

  test("an undecodable frame is a malformed sentinel, not a drop", () => {
    const { seen, ingest } = collect({ methodNames: METHOD_NAMES });
    ingest({ channelId: "myapp.dot", dir: "out", frame: new Uint8Array([0xff]) });

    expect(seen).toHaveLength(1);
    expect(seen[0]).toMatchObject({
      role: "malformed",
      requestId: "malformed",
      frameId: -1,
      byteLength: 1,
    });
  });
});

describe("every consumer sees the resolved role, not just the view adapter", () => {
  test("the formatted sink line names the role, not 'unknown'", () => {
    const lines: string[] = [];
    const wireDebugger = createWireDebugger({
      methodNames: METHOD_NAMES,
      sink: (line) => lines.push(line),
    });
    const ingest = createDebugIngest(wireDebugger.observe, {
      methodNames: METHOD_NAMES,
    });

    ingest(envelope("p:1", W.ACCOUNT_GET_ACCOUNT.request));

    // This is the line the default `console.debug` sink prints. It read
    // "-> unknown account.getAccount" while role was resolved only downstream.
    expect(lines[0]).toBe(
      `[wire p:1] → request account.getAccount (id=${W.ACCOUNT_GET_ACCOUNT.request}, 1B)`,
    );
  });

  test("the forward hook receives the resolved role", () => {
    const forwarded: ObservedFrame[] = [];
    const wireDebugger = createWireDebugger({
      methodNames: METHOD_NAMES,
      sink: () => {},
      forward: (frame) => forwarded.push(frame),
    });
    const ingest = createDebugIngest(wireDebugger.observe, {
      methodNames: METHOD_NAMES,
    });

    ingest(envelope("p:1", W.ACCOUNT_GET_ACCOUNT.request));

    expect(forwarded).toHaveLength(1);
    expect(forwarded[0]?.role).toBe("request");
  });
});

describe("ingest clamps ids and gates raw bytes", () => {
  test("channelId and requestId are clamped to the same bound", () => {
    const long = "x".repeat(DEFAULT_MAX_ID_CHARS + 100);
    const { seen, ingest } = collect({ methodNames: METHOD_NAMES });

    ingest(
      envelope(long, W.ACCOUNT_GET_ACCOUNT.request, new Uint8Array([0]), "out", long),
    );

    expect(seen[0]?.channelId).toHaveLength(DEFAULT_MAX_ID_CHARS);
    expect(seen[0]?.requestId).toHaveLength(DEFAULT_MAX_ID_CHARS);
  });

  test("maxIdChars overrides the default bound", () => {
    const { seen, ingest } = collect({ maxIdChars: 4 });
    ingest(envelope("p:1234567890", W.ACCOUNT_GET_ACCOUNT.request));
    expect(seen[0]?.requestId).toBe("p:12");
  });

  test("raw bytes are attached only under retainBytes", () => {
    const off = collect({ methodNames: METHOD_NAMES });
    off.ingest(envelope("p:1", W.ACCOUNT_GET_ACCOUNT.request, new Uint8Array([7])));
    expect(off.seen[0]?.bytes).toBeUndefined();
    // Byte length is recorded either way.
    expect(off.seen[0]?.byteLength).toBe(1);

    const on = collect({ methodNames: METHOD_NAMES, retainBytes: true });
    on.ingest(envelope("p:1", W.ACCOUNT_GET_ACCOUNT.request, new Uint8Array([7])));
    expect(Array.from(on.seen[0]?.bytes ?? [])).toEqual([7]);
  });

  test("the product-vantage direction is carried through untouched", () => {
    const { seen, ingest } = collect({ methodNames: METHOD_NAMES });
    ingest(envelope("p:1", W.ACCOUNT_GET_ACCOUNT.request, new Uint8Array([0]), "out"));
    ingest(envelope("p:1", W.ACCOUNT_GET_ACCOUNT.response, new Uint8Array([0]), "in"));
    expect(seen.map((f) => f.direction)).toEqual(["out", "in"]);
  });
});
