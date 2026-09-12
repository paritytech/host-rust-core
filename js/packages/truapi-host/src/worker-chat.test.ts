import { describe, expect, it } from "bun:test";

import { handlePublishChatAction } from "./worker-chat.js";
import type { WorkerProductRuntime } from "./wasm-module.js";
import type { WorkerToMain } from "./worker-protocol.js";

function fakeCore(log: string[]): WorkerProductRuntime {
  return {
    receiveFrame: async () => {},
    dispose: () => {},
    free: () => {},
    publishChatAction: (action) => log.push(`chat:${action.join(",")}`),
    publishRendererAction: (item) => log.push(`renderer:${item.join(",")}`),
    render: () => ({ cancel: () => {}, free: () => {} }),
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

  it("acknowledges an action the core accepted", () => {
    const messages: WorkerToMain[] = [];
    const log: string[] = [];

    handlePublishChatAction(
      fakeCore(log),
      (msg) => messages.push(msg),
      1,
      2,
      new Uint8Array([7]),
    );

    expect(log).toEqual(["chat:7"]);
    expect(messages).toEqual([
      { kind: "publishChatActionResponse", requestId: 2, ok: true },
    ]);
  });
});
