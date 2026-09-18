import { describe, expect, it } from "bun:test";
import { ok } from "neverthrow";

import type { CoreStorageKey } from "../generated/host-callbacks.js";
import { createMockHost, mockRuntimeConfig } from "./create-mock-host.js";
import { createWebWorkerPairingHostRuntime } from "./index.js";

/** Lowercase hex without `0x`. */
function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

describe("createMockHost callbacks", () => {
  it("product storage round-trips and is namespaced from core", async () => {
    const { callbacks } = createMockHost();
    await callbacks.productStorage.write("k", new Uint8Array([1, 2, 3]));
    expect(await callbacks.productStorage.read("k")).toEqual(
      new Uint8Array([1, 2, 3]),
    );
    // A product key never collides with a core slot.
    expect(
      await callbacks.coreStorage.readCoreStorage({ tag: "AuthSession" }),
    ).toBeUndefined();
    await callbacks.productStorage.clear("k");
    expect(await callbacks.productStorage.read("k")).toBeUndefined();
  });

  it("core storage round-trips per slot", async () => {
    const { callbacks } = createMockHost();
    const key: CoreStorageKey = {
      tag: "PermissionAuthorization",
      value: { productId: "p", request: { tag: "Device", value: "Camera" } },
    };
    await callbacks.coreStorage.writeCoreStorage(key, new Uint8Array([9]));
    expect(await callbacks.coreStorage.readCoreStorage(key)).toEqual(
      new Uint8Array([9]),
    );
    await callbacks.coreStorage.clearCoreStorage(key);
    expect(await callbacks.coreStorage.readCoreStorage(key)).toBeUndefined();
  });

  it("permissions follow per-capability policy", async () => {
    const { callbacks } = createMockHost({
      devicePermissions: "allow-all",
      remotePermissions: "deny-all",
    });
    expect(
      (await callbacks.permissions.devicePermission("Notifications")).granted,
    ).toBe(true);
    expect(
      (
        await callbacks.permissions.remotePermission({
          permission: { tag: "WebRtc" },
        })
      ).granted,
    ).toBe(false);
  });

  it("feature support and theme reflect config", async () => {
    const { callbacks } = createMockHost({
      featureSupported: false,
      theme: "Light",
    });
    expect(
      (
        await callbacks.features.featureSupported({
          tag: "Chain",
          value: { genesisHash: "0x00" },
        })
      ).supported,
    ).toBe(false);
    const theme = await callbacks.theme
      .subscribeTheme()
      [Symbol.asyncIterator]()
      .next();
    expect(theme.value).toEqual(ok({ name: { tag: "Default" }, variant: "Light" }));
  });

  it("records navigations and assigns monotonic notification ids", async () => {
    const host = createMockHost();
    await host.callbacks.navigation.navigateTo("https://a");
    await host.callbacks.navigation.navigateTo("https://b");
    expect(host.getNavigationLog()).toEqual(["https://a", "https://b"]);

    const first = await host.callbacks.notifications.pushNotification({
      text: "one",
    });
    const second = await host.callbacks.notifications.pushNotification({
      text: "two",
    });
    expect([first.id, second.id]).toEqual([1, 2]);
    expect(host.getNotificationLog().length).toBe(2);
  });

  it("confirms per config and records chain sends", async () => {
    const denied = createMockHost({ confirmUserActions: false });
    expect(
      await denied.callbacks.userConfirmation.confirmUserAction({
        tag: "ResourceAllocation",
        value: { callingProductId: "mock.dot", resources: [] },
      }),
    ).toBe(false);

    const host = createMockHost();
    const conn = await host.callbacks.chain.connect(new Uint8Array(32));
    conn.send("rpc-1");
    expect(host.sentRpc()).toEqual(["rpc-1"]);
  });

  it("replays scripted chain frames", async () => {
    const host = createMockHost({ chainResponses: ["f1", "f2"] });
    const conn = await host.callbacks.chain.connect(new Uint8Array(32));
    const frames: string[] = [];
    for await (const frame of conn.responses()) {
      frames.push(frame);
    }
    expect(frames).toEqual(["f1", "f2"]);
  });

  it("records confirmations and cancelled notifications", async () => {
    const host = createMockHost();
    await host.callbacks.userConfirmation.confirmUserAction({
      tag: "ResourceAllocation",
      value: { callingProductId: "mock.dot", resources: [] },
    });
    expect(host.confirmations()).toEqual(["ResourceAllocation"]);

    const { id } = await host.callbacks.notifications.pushNotification({
      text: "x",
    });
    await host.callbacks.notifications.cancelNotification(id);
    expect(host.cancelledNotifications()).toEqual([id]);
  });

  it("chainClosed ends the response stream immediately", async () => {
    const host = createMockHost({ chainClosed: true });
    const conn = await host.callbacks.chain.connect(new Uint8Array(32));
    const first = await conn.responses()[Symbol.asyncIterator]().next();
    expect(first.done).toBe(true);
  });

  it("preimage insert then lookup round-trips", async () => {
    // The core owns Bulletin submission on current core; the host only
    // retrieves content, so tests seed the content store directly.
    const host = createMockHost();
    const key = host.seedPreimage(new Uint8Array([1, 2, 3]));
    // The key is the content address the core asks for, not an arbitrary
    // digest: the core recomputes blake2b-256 over whatever comes back and
    // reports a mismatch as a miss, so a key derived any other way makes every
    // seeded preimage unreachable through the core. The expected value is the
    // published blake2b-256 of `[1, 2, 3]`, so this fails even if the mock and
    // its Rust sibling change algorithm together.
    expect(hex(key)).toBe(
      "11c0e79b71c3976ccd0c02d1310e2516c08edc9d8b6f57ccd680d63a4d8e72da",
    );
    const found = await host.callbacks.preimage
      .lookupPreimage(key)
      [Symbol.asyncIterator]()
      .next();
    expect(found.value).toEqual(ok(new Uint8Array([1, 2, 3])));
  });

  it("preimage lookup misses on an unknown key", async () => {
    const host = createMockHost();
    host.seedPreimage(new Uint8Array([1, 2, 3]));
    const miss = await host.callbacks.preimage
      .lookupPreimage(new Uint8Array(32).fill(9))
      [Symbol.asyncIterator]()
      .next();
    expect(miss.value).toEqual(ok(undefined));
  });

  it("permission policy can deny device and allow remote", async () => {
    const { callbacks } = createMockHost({
      devicePermissions: "deny-all",
      remotePermissions: "allow-all",
    });
    expect(
      (await callbacks.permissions.devicePermission("Notifications")).granted,
    ).toBe(false);
    expect(
      (
        await callbacks.permissions.remotePermission({
          permission: { tag: "WebRtc" },
        })
      ).granted,
    ).toBe(true);
  });

  it("records auth-state transitions in order", () => {
    const host = createMockHost();
    host.callbacks.auth.authStateChanged({ tag: "Disconnected" });
    host.callbacks.auth.authStateChanged({
      tag: "Pairing",
      value: { deeplink: "dl" },
    });
    expect(host.authStates().map((state) => state.tag)).toEqual([
      "Disconnected",
      "Pairing",
    ]);
  });

  it("silent chain records sends but never yields a response", async () => {
    const host = createMockHost();
    const conn = await host.callbacks.chain.connect(new Uint8Array(32));
    conn.send("req");
    expect(host.sentRpc()).toEqual(["req"]);
    // Silent (no frames, not closed): the stream parks rather than yielding or
    // ending, so a race against a timer must be won by the timer.
    const outcome = await Promise.race([
      conn
        .responses()
        [Symbol.asyncIterator]()
        .next()
        .then(() => "yielded" as const),
      new Promise<"parked">((resolve) => setTimeout(() => resolve("parked"), 20)),
    ]);
    expect(outcome).toBe("parked");
  });
});

/** Minimal `Worker` stand-in: records posted messages and lets the test drive
 *  the `message` event by hand, so the provider initializes without real WASM. */
class FakeWorker {
  listeners = new Map<string, Set<(event: unknown) => void>>();
  messages: Record<string, unknown>[] = [];

  addEventListener(name: string, fn: (event: unknown) => void) {
    const set = this.listeners.get(name) ?? new Set();
    set.add(fn);
    this.listeners.set(name, set);
  }

  removeEventListener(name: string, fn: (event: unknown) => void) {
    this.listeners.get(name)?.delete(fn);
  }

  postMessage(message: Record<string, unknown>) {
    this.messages.push(message);
  }

  terminate() {}

  emit(message: Record<string, unknown>) {
    for (const listener of this.listeners.get("message") ?? []) {
      listener({ data: message });
    }
  }
}

describe("createMockHost with createWebWorkerPairingHostRuntime", () => {
  it("initializes a worker provider with the mock callbacks (no real WASM)", async () => {
    const worker = new FakeWorker();
    const host = createMockHost();
    const { productId, ...hostConfig } = mockRuntimeConfig();
    const runtimePromise = createWebWorkerPairingHostRuntime(
      worker as unknown as Worker,
      host.callbacks,
      { hostConfig },
    );
    worker.emit({ kind: "loaded" });
    worker.emit({ kind: "ready" });
    const runtime = await runtimePromise;

    const providerPromise = runtime.createProvider({ productId });
    const createCore = [...worker.messages]
      .reverse()
      .find((m) => m.kind === "createCore");
    expect(createCore).toBeDefined();
    worker.emit({ kind: "coreReady", coreId: createCore!.coreId });

    const provider = await providerPromise;
    expect(provider).toBeDefined();
    const init = worker.messages.find((message) => message.kind === "init");
    expect(init).toBeDefined();

    provider.dispose();
    runtime.dispose();
  });
});

describe("createMockHost control surface", () => {
  const review = (callingProductId: string) =>
    ({
      tag: "ResourceAllocation",
      value: { callingProductId, resources: [] },
    }) as const;

  it("records review payloads, not just kinds", async () => {
    // Two reviews of the same kind with different payloads: a kind-only
    // recording cannot tell these apart.
    const host = createMockHost();
    await host.callbacks.userConfirmation.confirmUserAction(review("first.dot"));
    await host.callbacks.userConfirmation.confirmUserAction(review("second.dot"));

    expect(host.confirmations()).toEqual([
      "ResourceAllocation",
      "ResourceAllocation",
    ]);
    expect(
      host.reviews().map((r) => (r as { value: { callingProductId: string } }).value.callingProductId),
    ).toEqual(["first.dot", "second.dot"]);
  });

  it("answers permissions per capability, overriding the policy", async () => {
    const host = createMockHost({ devicePermissions: "deny-all" });
    const ask = () => host.callbacks.permissions.devicePermission("Camera");

    expect((await ask()).granted).toBe(false);
    host.grantPermission("Camera");
    expect((await ask()).granted).toBe(true);
    // Per permission, not a policy flip.
    expect(
      (await host.callbacks.permissions.devicePermission("Microphone")).granted,
    ).toBe(false);
    expect(host.getGrantedPermissions()).toEqual(["Camera"]);

    host.resetPermission("Camera");
    expect((await ask()).granted).toBe(false);
  });

  it("denies whatever was not explicitly granted when enforcing", async () => {
    const host = createMockHost();
    host.setEnforcePermissions(true);
    expect(
      (await host.callbacks.permissions.devicePermission("Camera")).granted,
    ).toBe(false);
    host.grantPermission("Camera");
    expect(
      (await host.callbacks.permissions.devicePermission("Camera")).granted,
    ).toBe(true);
  });

  it("records the surface, key and answer of every permission prompt", async () => {
    const host = createMockHost();
    host.revokePermission("Camera");
    await host.callbacks.permissions.devicePermission("Camera");
    expect(host.getPermissionLog()).toEqual([
      { tag: "Camera", value: "Camera", approved: false, kind: "device" },
    ]);
  });

  it("throws descriptively for domains the mock cannot model", () => {
    const host = createMockHost();
    // Never a faked success for a path the real host cannot execute, and the
    // error has to say WHY so the reader knows whether it is a gap or a
    // deliberate limit.
    expect(
      () => (host.payment as unknown as { setBalance: unknown }).setBalance,
    ).toThrow(/no host implements them/);
    expect(
      () => (host.coinPayment as unknown as { transfer: unknown }).transfer,
    ).toThrow(/no host implements them/);
    expect(
      () =>
        (host.statements as unknown as { getSubmitted: unknown }).getSubmitted,
    ).toThrow(/people chain/);
  });

  it("reset returns the mock to its constructed state", async () => {
    const host = createMockHost();
    await host.callbacks.navigation.navigateTo("https://a");
    await host.callbacks.userConfirmation.confirmUserAction(review("mock.dot"));
    host.seedPreimage(new Uint8Array([1]));
    host.setTheme("Light");
    host.setEnforcePermissions(true);
    host.revokePermission("Camera");

    host.reset();

    expect(host.getNavigationLog()).toEqual([]);
    expect(host.reviews()).toEqual([]);
    expect(host.getPermissionLog()).toEqual([]);
    expect(host.getGrantedPermissions()).toEqual([]);
    expect(host.getPreimages()).toEqual([]);
    expect(host.getTheme()).toBe("Dark");
    expect(
      (await host.callbacks.permissions.devicePermission("Camera")).granted,
    ).toBe(true);
  });
});

describe("createMockHost TestHostAPI parity", () => {
  const signRaw = {
    tag: "SignRaw",
    value: { Product: { request: { account: "a", payload: { Bytes: [1] } } } },
  } as const;
  const allocation = {
    tag: "ResourceAllocation",
    value: { callingProductId: "mock.dot", resources: [] },
  } as const;

  it("getSigningLog reports only the reviews that gate a signature", async () => {
    const host = createMockHost();
    // A non-signing review must not appear in a signing log.
    await host.callbacks.userConfirmation.confirmUserAction(allocation);
    await host.callbacks.userConfirmation.confirmUserAction(signRaw);

    expect(host.reviews()).toHaveLength(2);
    const log = host.getSigningLog();
    expect(log).toHaveLength(1);
    expect(log[0].type).toBe("raw");
    expect(log[0].payload).toEqual(signRaw.value);

    host.clearSigningLog();
    expect(host.getSigningLog()).toEqual([]);
  });

  it("getIsAuthenticated follows the last auth state the core reported", async () => {
    const host = createMockHost();
    expect(host.getIsAuthenticated()).toBe(false);
    await host.callbacks.auth.authStateChanged({ tag: "Connected", value: {} });
    expect(host.getIsAuthenticated()).toBe(true);
    await host.callbacks.auth.authStateChanged({ tag: "Disconnected" });
    expect(host.getIsAuthenticated()).toBe(false);
  });

  it("setPermissionBehavior switches the fallback for both prompts", async () => {
    const host = createMockHost();
    host.setPermissionBehavior("deny-all");
    expect(
      (await host.callbacks.permissions.devicePermission("Camera")).granted,
    ).toBe(false);
    expect(
      (
        await host.callbacks.permissions.remotePermission({
          permission: { tag: "ChainSubmit" },
        })
      ).granted,
    ).toBe(false);
    // An explicit grant still wins over the policy.
    host.grantPermission("Camera");
    expect(
      (await host.callbacks.permissions.devicePermission("Camera")).granted,
    ).toBe(true);
  });

  it("getConnectionStatus and dispose track and release state", async () => {
    const host = createMockHost();
    expect(host.getConnectionStatus()).toBe("Idle");
    host.simulateDisconnect();
    expect(host.getConnectionStatus()).toBe("Disconnected");

    await host.callbacks.navigation.navigateTo("https://a");
    host.dispose();
    expect(host.getNavigationLog()).toEqual([]);
    expect(host.getConnectionStatus()).toBe("Idle");
  });
});

describe("the notification log", () => {
  it("records an entry per push and flips cancelled by id", async () => {
    const host = createMockHost();
    const { callbacks } = host;

    const first = await callbacks.notifications.pushNotification({
      text: "one",
      scheduledAt: 1_700_000_000_000n,
    });
    const second = await callbacks.notifications.pushNotification({
      text: "two",
      deeplink: "https://example.test/x",
    });
    // Ids are what the product cancels by, so they have to be distinct -- and
    // positive, since a product that reads 0 as "no id" cannot cancel by it.
    expect(first.id).not.toBe(second.id);
    expect(first.id).toBeGreaterThan(0);

    const scheduled = host.getNotificationLog();
    expect(scheduled).toHaveLength(2);
    expect(scheduled[0]).toMatchObject({
      id: first.id,
      text: "one",
      scheduledAt: 1_700_000_000_000n,
      cancelled: false,
    });
    expect(scheduled[1]).toMatchObject({
      id: second.id,
      deeplink: "https://example.test/x",
      cancelled: false,
    });

    await callbacks.notifications.cancelNotification(first.id);

    const afterCancel = host.getNotificationLog();
    // The cancelled one flips in place; the other is untouched. Asserting both
    // is what catches a cancel that marks the whole log.
    expect(afterCancel.find((n) => n.id === first.id)?.cancelled).toBe(true);
    expect(afterCancel.find((n) => n.id === second.id)?.cancelled).toBe(false);
  });

  it("hands out copies, so a caller cannot mutate the host's log", async () => {
    const host = createMockHost();
    const { callbacks } = host;
    await callbacks.notifications.pushNotification({ text: "one" });

    host.getNotificationLog()[0]!.cancelled = true;

    expect(host.getNotificationLog()[0]!.cancelled).toBe(false);
  });
});

describe("statement injection through the chain connection", () => {
  // A minimal socket the proxy can drive, so the test exercises the real
  // subscribe-reply parsing rather than a stand-in for it.
  class FakeSocket {
    static instances: FakeSocket[] = [];
    listeners: Record<string, ((e: unknown) => void)[]> = {};
    sent: string[] = [];
    constructor(public url: string) {
      FakeSocket.instances.push(this);
      queueMicrotask(() => this.emit("open", {}));
    }
    addEventListener(type: string, fn: (e: unknown) => void) {
      (this.listeners[type] ??= []).push(fn);
    }
    emit(type: string, event: unknown) {
      for (const fn of this.listeners[type] ?? []) fn(event);
    }
    send(data: string) {
      this.sent.push(data);
    }
    close() {
      this.emit("close", {});
    }
  }

  async function connected() {
    const original = globalThis.WebSocket;
    FakeSocket.instances = [];
    (globalThis as { WebSocket: unknown }).WebSocket = FakeSocket;
    const host = createMockHost({ chainProxies: [{ rpcUrl: "ws://chain.test" }] });
    const conn = await host.callbacks.chain.connect(new Uint8Array(32));
    (globalThis as { WebSocket: unknown }).WebSocket = original;
    return { host, conn, socket: FakeSocket.instances[0]! };
  }

  it("delivers an injected statement to a live subscription", async () => {
    const { host, conn, socket } = await connected();
    const reader = conn.responses()[Symbol.asyncIterator]();

    conn.send(
      JSON.stringify({
        jsonrpc: "2.0",
        id: "truapi:1",
        method: "statement_subscribeStatement",
        params: [{ matchAll: [] }],
      }),
    );
    // The chain answers with the subscription id; that reply is what makes
    // injection addressable.
    socket.emit("message", {
      data: JSON.stringify({ jsonrpc: "2.0", id: "truapi:1", result: "sub-1" }),
    });
    await reader.next();

    expect(host.injectStatement(new Uint8Array([1, 2, 3]))).toBe(1);

    // Compared whole: the core reads `result.data.statements`, and asserting
    // the fields one by one would not catch an envelope carrying extra keys.
    expect(JSON.parse((await reader.next()).value as string)).toEqual({
      jsonrpc: "2.0",
      method: "statement_subscribeStatement",
      params: {
        subscription: "sub-1",
        result: {
          event: "newStatements",
          data: { statements: ["0x010203"], remaining: 0 },
        },
      },
    });
  });

  it("reaches nothing before the product subscribes", async () => {
    const { host } = await connected();
    // No subscribe reply seen, so there is no id to address: reporting a
    // delivery here would let a suite think the product got something.
    expect(host.injectStatement("0xab")).toBe(0);
  });

  it("records what was injected and clears it", async () => {
    const { host } = await connected();
    host.injectStatement(new Uint8Array([0xaa]));
    host.injectStatement("0xbb");
    expect(host.getInjectedStatements()).toEqual(["0xaa", "0xbb"]);
    host.clearStatements();
    expect(host.getInjectedStatements()).toEqual([]);
  });
});

describe("reading back submitted statements", () => {
  it("returns the hex the core put on the wire, in order", async () => {
    const original = globalThis.WebSocket;
    (globalThis as { WebSocket: unknown }).WebSocket = class {
      constructor(public url: string) {}
      addEventListener() {}
      send() {}
      close() {}
    };
    const host = createMockHost({ chainProxies: [{ rpcUrl: "ws://chain.test" }] });
    const conn = await host.callbacks.chain.connect(new Uint8Array(32));
    (globalThis as { WebSocket: unknown }).WebSocket = original;

    const submit = (hex: string, id: number) =>
      JSON.stringify({
        jsonrpc: "2.0",
        id: `truapi:${id}`,
        method: "statement_submit",
        params: [hex],
      });

    conn.send(submit("0xaabb", 1));
    // Other chain traffic must not be mistaken for a submission.
    conn.send(
      JSON.stringify({
        jsonrpc: "2.0",
        id: "truapi:2",
        method: "statement_subscribeStatement",
        params: [{ matchAll: [] }],
      }),
    );
    // An unsubscribe carries a STRING first param, so it is what a filter that
    // forgot to check the method would wrongly report as a submitted statement.
    conn.send(
      JSON.stringify({
        jsonrpc: "2.0",
        id: "truapi:3",
        method: "statement_unsubscribeStatement",
        params: ["z9VCGBlbLFl58Rp4"],
      }),
    );
    conn.send(submit("0xccdd", 4));

    expect(host.getSubmittedStatements()).toEqual(["0xaabb", "0xccdd"]);
  });

  it("is empty when the product has submitted nothing", async () => {
    const host = createMockHost();
    expect(host.getSubmittedStatements()).toEqual([]);
  });
});
