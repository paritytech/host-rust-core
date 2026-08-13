import { describe, expect, test } from "bun:test";

import { createWireDebugger, type WireMethodInfo } from "./wire-debugger.js";
import type { FrameRole, ObservedFrame } from "./observed-frame.js";

/** A minimal observed frame; only the fields the trace engine keys/groups on matter. */
function frame(
  channelId: string,
  requestId: string,
  frameId: number,
  timestamp: number,
  role: FrameRole = "unknown",
): ObservedFrame {
  return {
    channelId,
    direction: "out",
    requestId,
    frameId,
    role,
    byteLength: 1,
    timestamp,
  };
}

/** The same frame, carrying `bytes` so the per-trace byte cap applies to it. */
function withBytes(
  requestId: string,
  frameId: number,
  timestamp: number,
  bytes: number,
  role: FrameRole = "unknown",
): ObservedFrame {
  return {
    ...frame("app.dot", requestId, frameId, timestamp, role),
    byteLength: bytes,
    bytes: new Uint8Array(bytes),
  };
}

describe("createWireDebugger grouping", () => {
  test("accumulates every frame of one op under (channel, requestId)", () => {
    // Regression guard: the request and its response share a channel + requestId
    // and must land in ONE trace. (A bug where lookup used the composite key but
    // re-insert used the bare requestId made every frame spawn a new 1-frame
    // trace, so nothing ever paired.)
    const wd = createWireDebugger({ sink: () => {} });
    wd.observe(frame("app.dot", "p:1", 22, 1)); // request
    wd.observe(frame("app.dot", "p:1", 23, 2)); // response

    const traces = wd.traces();
    expect(traces).toHaveLength(1);
    expect(traces[0].frames).toHaveLength(2);
    expect(traces[0].frames.map((f) => f.frameId)).toEqual([22, 23]);
    expect(traces[0].channelId).toBe("app.dot");
  });

  test("a long subscription keeps accumulating under one trace", () => {
    const wd = createWireDebugger({ sink: () => {} });
    wd.observe(frame("app.dot", "s:7", 18, 1)); // start
    for (let i = 0; i < 50; i++) {
      wd.observe(frame("app.dot", "s:7", 21, 2 + i)); // receive
    }
    const traces = wd.traces();
    expect(traces).toHaveLength(1);
    expect(traces[0].frames).toHaveLength(51);
  });

  test("does not merge the same requestId across channels", () => {
    const wd = createWireDebugger({ sink: () => {} });
    wd.observe(frame("hostA.dot", "p:1", 22, 1));
    wd.observe(frame("hostB.dot", "p:1", 80, 2));

    const traces = wd.traces();
    expect(traces).toHaveLength(2);
    expect(new Set(traces.map((t) => t.channelId))).toEqual(
      new Set(["hostA.dot", "hostB.dot"]),
    );
  });

  test("trace() resolves by requestId, disambiguated by channel", () => {
    const wd = createWireDebugger({ sink: () => {} });
    wd.observe(frame("hostA.dot", "p:1", 22, 1));
    wd.observe(frame("hostB.dot", "p:1", 80, 2));

    // With a channel, the exact trace; without, the first match by requestId.
    expect(wd.trace("p:1", "hostB.dot")?.frames[0].frameId).toBe(80);
    expect(wd.trace("p:1", "hostA.dot")?.frames[0].frameId).toBe(22);
    expect(wd.trace("p:1")).toBeDefined();
    expect(wd.trace("nope")).toBeUndefined();
  });

  test("tracesForChannel filters to one channel", () => {
    const wd = createWireDebugger({ sink: () => {} });
    wd.observe(frame("hostA.dot", "p:1", 22, 1));
    wd.observe(frame("hostA.dot", "p:2", 24, 2));
    wd.observe(frame("hostB.dot", "p:1", 80, 3));

    expect(wd.tracesForChannel("hostA.dot")).toHaveLength(2);
    expect(wd.tracesForChannel("hostB.dot")).toHaveLength(1);
    expect(wd.tracesForChannel("absent.dot")).toHaveLength(0);
  });

  test("counts whole-op evictions so ops aren't silently under-reported", () => {
    const wd = createWireDebugger({ sink: () => {}, maxTraces: 2 });
    // Four distinct ops under a cap of 2: the two oldest whole ops are evicted.
    // traces() shows only survivors, so evictedTraces() is the only signal that
    // the other two happened.
    wd.observe(frame("app.dot", "p:1", 22, 1));
    wd.observe(frame("app.dot", "p:2", 22, 2));
    wd.observe(frame("app.dot", "p:3", 22, 3));
    wd.observe(frame("app.dot", "p:4", 22, 4));
    expect(wd.traces().length).toBe(2);
    expect(wd.evictedTraces()).toBe(2);
    wd.clear();
    expect(wd.evictedTraces()).toBe(0);
  });

  test("a recycled requestId opens a new op instead of merging (generation)", () => {
    // Regression for real dotli traffic: a product recycles `p:5` for an unrelated
    // later call. Mirror real ingest — frames arrive role "unknown" and the opener
    // is resolved from the frameId's wire-table kind — so the split must still fire.
    const methodNames = new Map<number, WireMethodInfo>([
      [40, { method: "chat.createRoom", kind: "request" }],
      [41, { method: "chat.createRoom", kind: "response" }],
      [22, { method: "account.getAccount", kind: "request" }],
      [23, { method: "account.getAccount", kind: "response" }],
    ]);
    const wd = createWireDebugger({ sink: () => {}, methodNames });
    wd.observe(frame("app.dot", "p:5", 40, 1)); // op 0: chat.createRoom (role "unknown")
    wd.observe(frame("app.dot", "p:5", 41, 2));
    wd.observe(frame("app.dot", "p:5", 22, 3_600_000)); // id reused: account.getAccount
    wd.observe(frame("app.dot", "p:5", 23, 3_600_002));

    const traces = wd.traces();
    expect(traces).toHaveLength(2);
    expect(traces.map((t) => t.frames.map((f) => f.frameId))).toEqual([
      [40, 41],
      [22, 23],
    ]);
    expect(traces.map((t) => t.generation)).toEqual([0, 1]);
    // Durations stay honest — neither op spans the hour-long gap between them.
    expect(traces[0].lastAt - traces[0].startedAt).toBe(1);
    expect(traces[1].lastAt - traces[1].startedAt).toBe(2);
    // trace() resolves to the latest generation.
    expect(wd.trace("p:5", "app.dot")?.frames[0].frameId).toBe(22);
  });

  test("the frame cap evicts from index 1, keeping the opener (frames[0])", () => {
    // Regression: evicting the oldest frame drops the subscription's `start`, so
    // pairing would falsely flag the live sub `orphaned`. The opener must survive.
    const wd = createWireDebugger({ sink: () => {}, maxFramesPerTrace: 3 });
    wd.observe(frame("app.dot", "s:7", 18, 1, "start")); // opener
    for (let i = 0; i < 10; i++) {
      wd.observe(frame("app.dot", "s:7", 21, 2 + i, "receive"));
    }
    const [trace] = wd.traces();
    expect(trace.frames).toHaveLength(3);
    // frames[0] is still the start (id 18), not a mid-stream receive.
    expect(trace.frames[0].frameId).toBe(18);
    expect(trace.frames[0].role).toBe("start");
    expect(trace.truncated).toBe(true);
  });

  test("an un-truncated trace is not marked truncated", () => {
    const wd = createWireDebugger({ sink: () => {}, maxFramesPerTrace: 100 });
    wd.observe(frame("app.dot", "p:1", 22, 1));
    wd.observe(frame("app.dot", "p:1", 23, 2));
    expect(wd.traces()[0].truncated).toBe(false);
  });

  test("the byte cap evicts payload frames but keeps the opener", () => {
    const wd = createWireDebugger({ sink: () => {}, maxBytesPerTrace: 100 });
    wd.observe(withBytes("s:9", 18, 1, 10, "start")); // opener, 10B
    for (let i = 0; i < 20; i++) {
      wd.observe(withBytes("s:9", 21, 2 + i, 40, "receive")); // 40B each
    }
    const [trace] = wd.traces();
    const retained = trace.frames.reduce(
      (n, f) => n + (f.bytes?.length ?? 0),
      0,
    );
    expect(retained).toBeLessThanOrEqual(100);
    expect(trace.frames[0].frameId).toBe(18); // opener kept
    expect(trace.truncated).toBe(true);
  });

  test("a single frame whose payload alone exceeds the byte cap sheds its bytes", () => {
    const wd = createWireDebugger({ sink: () => {}, maxBytesPerTrace: 100 });
    // The opener alone is 500B — larger than the whole 100B budget. It must stay
    // resident as a frame (pairing/retry-storm key on frames[0]) but shed its
    // bytes so it can't pin more than the cap.
    wd.observe(withBytes("s:1", 18, 1, 500, "start"));
    const [trace] = wd.traces();
    expect(trace.frames).toHaveLength(1);
    expect(trace.frames[0].frameId).toBe(18); // frame kept
    expect(trace.frames[0].byteLength).toBe(500); // metadata kept
    expect(trace.frames[0].bytes).toBeUndefined(); // oversized bytes shed
    const retained = trace.frames.reduce(
      (n, f) => n + (f.bytes?.length ?? 0),
      0,
    );
    expect(retained).toBeLessThanOrEqual(100);
    expect(trace.truncated).toBe(true);
  });

  test("a completed op under the byte cap keeps its response", () => {
    // 700B request + 400B response under a 1000B cap: neither frame is over
    // budget on its own, and the op is finished. Charging the opener's 700B to a
    // budget the eviction loop reclaims from evicted the *response* of a
    // completed op, which then read as `orphaned` (and, in the op list, as a
    // call still waiting).
    const wd = createWireDebugger({ sink: () => {}, maxBytesPerTrace: 1000 });
    wd.observe(withBytes("p:1", 22, 1, 700, "request"));
    wd.observe(withBytes("p:1", 23, 2, 400, "response"));

    const [trace] = wd.traces();
    expect(trace.frames.map((f) => f.frameId)).toEqual([22, 23]);
    expect(trace.frames[1].bytes?.length).toBe(400);
    expect(trace.dropped.framesByBytes).toBe(0);
    expect(trace.truncated).toBe(false);
  });

  test("an opener whose payload equals the byte cap does not evict every later frame", () => {
    // The opener is exempt from eviction but used to be counted, so a trace whose
    // opener alone filled the budget was permanently over it: every subsequent
    // frame was evicted on arrival and the trace could never hold more than the
    // opener. 20 receives observed, 1 frame retained, unrecoverable.
    const wd = createWireDebugger({ sink: () => {}, maxBytesPerTrace: 100 });
    wd.observe(withBytes("s:2", 18, 1, 100, "start")); // opener exactly at the cap
    for (let i = 0; i < 20; i++) {
      wd.observe(withBytes("s:2", 21, 2 + i, 1, "receive")); // 1B each
    }
    const [trace] = wd.traces();
    expect(trace.frames).toHaveLength(21);
    expect(trace.dropped.framesByBytes).toBe(0);
    expect(trace.truncated).toBe(false);
  });

  test("dropped counts the two cap axes separately", () => {
    // A boolean `truncated` renders "1 frame lost" and "77 lost" identically and
    // cannot say which cap took them.
    const byCount = createWireDebugger({
      sink: () => {},
      maxFramesPerTrace: 3,
    });
    byCount.observe(frame("app.dot", "s:7", 18, 1, "start"));
    for (let i = 0; i < 10; i++) {
      byCount.observe(frame("app.dot", "s:7", 21, 2 + i, "receive"));
    }
    const counted = byCount.traces()[0];
    expect(counted.dropped).toEqual({
      framesByCount: 8,
      framesByBytes: 0,
      payloadsShed: 0,
    });
    expect(counted.truncated).toBe(true);

    const byBytes = createWireDebugger({
      sink: () => {},
      maxBytesPerTrace: 100,
    });
    byBytes.observe(withBytes("s:8", 18, 1, 10, "start"));
    for (let i = 0; i < 20; i++) {
      byBytes.observe(withBytes("s:8", 21, 2 + i, 40, "receive"));
    }
    const bytesTrace = byBytes.traces()[0];
    expect(bytesTrace.dropped.framesByCount).toBe(0);
    expect(bytesTrace.dropped.framesByBytes).toBeGreaterThan(0);
    expect(bytesTrace.dropped.payloadsShed).toBe(0);
  });

  test("a shed payload counts on its own axis, not as a lost frame", () => {
    // The frame is still in the sequence with its metadata — nothing is missing
    // from the op, so pairing stays sound even though bytes are gone.
    const wd = createWireDebugger({ sink: () => {}, maxBytesPerTrace: 100 });
    wd.observe(withBytes("s:3", 18, 1, 500, "start"));
    const [trace] = wd.traces();
    expect(trace.dropped).toEqual({
      framesByCount: 0,
      framesByBytes: 0,
      payloadsShed: 1,
    });
    expect(trace.truncated).toBe(true);
  });

  test("receives never rotate; a re-subscribe (second start) opens a new op", () => {
    const wd = createWireDebugger({ sink: () => {} });
    wd.observe(frame("app.dot", "s:1", 18, 1, "start"));
    wd.observe(frame("app.dot", "s:1", 21, 2, "receive"));
    wd.observe(frame("app.dot", "s:1", 21, 3, "receive"));
    expect(wd.traces()).toHaveLength(1); // one live sub — receives append, no rotate

    wd.observe(frame("app.dot", "s:1", 18, 100, "start")); // id recycled for a new sub
    const traces = wd.traces();
    expect(traces).toHaveLength(2);
    expect(traces.map((t) => t.frames.length)).toEqual([3, 1]);
    expect(traces.map((t) => t.generation)).toEqual([0, 1]);
  });
});
