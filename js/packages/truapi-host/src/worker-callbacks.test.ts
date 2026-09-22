import { describe, expect, it } from "bun:test";

import {
  createWorkerRawCallbacks,
  startRawSubscription,
} from "./generated/worker-callbacks.js";
import type { RawCallbacks } from "./generated/host-callbacks-adapter.js";
import type { WorkerCallbackBridge } from "./generated/worker-callbacks.js";

// The worker proxies an optional capability only when the main thread reports
// the host serves it, so the core sees the same capability set on both sides of
// the boundary. Without that gate a worker host would always look chat-capable
// and the core would route chat calls at a host that cannot answer them.

function stubBridge() {
  const requests: { name: string; args: readonly unknown[] }[] = [];
  const subscriptions: { name: string; payload: Uint8Array | string | null }[] =
    [];
  return {
    requests,
    subscriptions,
    bridge: {
      callbackRequest: async (name: string, args: readonly unknown[]) => {
        requests.push({ name, args });
        return new Uint8Array();
      },
      startSubscription: (
        name: string,
        payload: Uint8Array | string | null,
      ) => {
        subscriptions.push({ name, payload });
        return () => {};
      },
      chainConnect: async () => null,
      hopConnect: async () => null,
    } satisfies WorkerCallbackBridge,
  };
}

describe("worker raw callbacks", () => {
  it("leaves username search unavailable when the host omits its capability", () => {
    const { bridge } = stubBridge();
    const callbacks = createWorkerRawCallbacks(bridge);

    expect(callbacks.identityUsernameCandidates).toBeUndefined();
  });

  it("omits the chat proxies when no chat capability is reported", () => {
    const { bridge } = stubBridge();

    const callbacks = createWorkerRawCallbacks(bridge);

    expect(callbacks.createChatRoom).toBeUndefined();
    expect(callbacks.postChatMessage).toBeUndefined();
    expect(callbacks.subscribeChatRooms).toBeUndefined();
    expect(callbacks.subscribeTheme).toBeDefined();
  });

  it("proxies chat through the bridge when the capability is reported", async () => {
    const { bridge, requests, subscriptions } = stubBridge();

    const callbacks = createWorkerRawCallbacks(bridge, { chat: true });

    const product = new Uint8Array([1]);
    await (
      callbacks.createChatRoom as (
        product: Uint8Array,
        request: Uint8Array,
      ) => Promise<unknown>
    )(product, new Uint8Array([2]));
    (
      callbacks.subscribeChatRooms as (
        product: Uint8Array,
        sendItem: () => void,
        sendError: () => void,
      ) => void
    )(
      product,
      () => {},
      () => {},
    );

    expect(requests.map((r) => r.name)).toContain("createChatRoom");
    expect(subscriptions).toEqual([
      { name: "subscribeChatRooms", payload: product },
    ]);
  });

  it("starts no chat room subscription when chat is absent", () => {
    const { bridge, subscriptions } = stubBridge();
    const callbacks = createWorkerRawCallbacks(bridge) as RawCallbacks;

    const stop = startRawSubscription(
      callbacks,
      "subscribeChatRooms",
      new Uint8Array([1]),
      () => {},
      () => {},
    );

    expect(stop).toBeUndefined();
    expect(subscriptions).toEqual([]);
  });

  it("omits the pocket proxies when no pocket capability is reported", () => {
    const { bridge } = stubBridge();

    const callbacks = createWorkerRawCallbacks(bridge);

    expect(callbacks.subscribePocketCards).toBeUndefined();
    expect(callbacks.removePocketCard).toBeUndefined();
  });

  it("proxies pocket through the bridge when the capability is reported", async () => {
    const { bridge, requests, subscriptions } = stubBridge();

    const callbacks = createWorkerRawCallbacks(bridge, { pocket: true });

    const product = new Uint8Array([1]);
    await (
      callbacks.removePocketCard as (
        product: Uint8Array,
        request: Uint8Array,
      ) => Promise<unknown>
    )(product, new Uint8Array([2]));
    (
      callbacks.subscribePocketCards as (
        product: Uint8Array,
        sendItem: () => void,
        sendError: () => void,
      ) => void
    )(
      product,
      () => {},
      () => {},
    );

    expect(requests.map((r) => r.name)).toContain("removePocketCard");
    expect(subscriptions).toEqual([
      { name: "subscribePocketCards", payload: product },
    ]);
  });
});
