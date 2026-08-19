import { describe, expect, it } from "bun:test";

import {
  handlePublishChatAction,
  handleRenderCustomMessageStart,
  stopRender,
  stopRendersForCore,
  type RenderSubscriptions,
} from "./worker-chat.js";
import type {
  WorkerCustomRendererSubscription,
  WorkerProductRuntime,
} from "./wasm-module.js";
import type { WorkerToMain } from "./worker-protocol.js";

function fakeSubscription(log: string[]): WorkerCustomRendererSubscription {
  return {
    cancel: () => log.push("cancel"),
    free: () => log.push("free"),
  };
}

/** Core stub that captures the render callbacks so a test can drive them. */
function fakeCore(
  log: string[],
  onStart?: (emit: {
    update: (node: Uint8Array) => void;
    complete: () => void;
    fail: (reason: string) => void;
  }) => void,
): WorkerProductRuntime {
  return {
    receiveFrame: async () => {},
    dispose: () => {},
    free: () => {},
    publishChatAction: (action) => log.push(`publish:${action.join(",")}`),
    renderCustomMessage: (
      _id,
      _type,
      _payload,
      onUpdate,
      onComplete,
      onError,
    ) => {
      onStart?.({ update: onUpdate, complete: onComplete, fail: onError });
      return fakeSubscription(log);
    },
  };
}

describe("worker chat entry points", () => {
  it("answers publishChatAction for an unknown core instead of throwing", () => {
    const messages: WorkerToMain[] = [];
    handlePublishChatAction(
      undefined,
      (msg) => messages.push(msg),
      4,
      9,
      new Uint8Array([1]),
    );
    expect(messages).toEqual([
      {
        kind: "publishChatActionResponse",
        requestId: 9,
        ok: false,
        error: "publishChatAction received for unknown core 4",
      },
    ]);
  });

  it("reports a core that refuses the action rather than dropping it", () => {
    const messages: WorkerToMain[] = [];
    const core = fakeCore([]);
    core.publishChatAction = () => {
      throw new Error("Denied");
    };

    handlePublishChatAction(
      core,
      (msg) => messages.push(msg),
      1,
      3,
      new Uint8Array([7]),
    );

    expect(messages).toEqual([
      {
        kind: "publishChatActionResponse",
        requestId: 3,
        ok: false,
        error: "Denied",
      },
    ]);
  });

  it("streams render items and releases the subscription on complete", () => {
    const messages: WorkerToMain[] = [];
    const log: string[] = [];
    const renders: RenderSubscriptions = new Map();
    let emit!: {
      update: (node: Uint8Array) => void;
      complete: () => void;
      fail: (reason: string) => void;
    };

    handleRenderCustomMessageStart(
      fakeCore(log, (e) => (emit = e)),
      (msg) => messages.push(msg),
      renders,
      1,
      5,
      "message",
      "vote",
      new Uint8Array([1]),
    );
    expect(renders.has(5)).toBe(true);

    emit.update(new Uint8Array([2, 3]));
    emit.complete();

    expect(messages).toEqual([
      {
        kind: "renderCustomMessageItem",
        renderId: 5,
        node: new Uint8Array([2, 3]),
      },
      { kind: "renderCustomMessageComplete", renderId: 5 },
    ]);
    // Completing must free the wasm handle, not just stop delivering.
    expect(log).toEqual(["cancel", "free"]);
    expect(renders.has(5)).toBe(false);
  });

  it("cancels only the renders belonging to the disposed core", () => {
    const log: string[] = [];
    const renders: RenderSubscriptions = new Map([
      [1, { coreId: 10, subscription: fakeSubscription(log) }],
      [2, { coreId: 11, subscription: fakeSubscription(log) }],
    ]);

    stopRendersForCore(renders, 10);

    expect([...renders.keys()]).toEqual([2]);
    expect(log).toEqual(["cancel", "free"]);
  });

  it("makes stopRender idempotent so a double dispose cannot double-free", () => {
    const log: string[] = [];
    const renders: RenderSubscriptions = new Map([
      [1, { coreId: 10, subscription: fakeSubscription(log) }],
    ]);

    stopRender(renders, 1);
    stopRender(renders, 1);

    expect(log).toEqual(["cancel", "free"]);
  });
  it("reports a declined render as an error, not a completion", () => {
    const messages: WorkerToMain[] = [];
    const log: string[] = [];
    const renders: RenderSubscriptions = new Map();
    let emit!: {
      update: (node: Uint8Array) => void;
      complete: () => void;
      fail: (reason: string) => void;
    };

    handleRenderCustomMessageStart(
      fakeCore(log, (e) => (emit = e)),
      (msg) => messages.push(msg),
      renders,
      1,
      6,
      "message",
      "vote",
      new Uint8Array(),
    );

    emit.update(new Uint8Array([9]));
    emit.fail("product interrupted the host-initiated subscription");

    // The partial tree must be followed by an error, never a completion.
    expect(messages).toEqual([
      {
        kind: "renderCustomMessageItem",
        renderId: 6,
        node: new Uint8Array([9]),
      },
      {
        kind: "renderCustomMessageError",
        renderId: 6,
        error: "product interrupted the host-initiated subscription",
      },
    ]);
    expect(renders.has(6)).toBe(false);
    expect(log).toEqual(["cancel", "free"]);
  });
});
