import { describe, expect, it } from "bun:test";
import { ok } from "neverthrow";

import type { CoreStorageKey } from "../generated/host-callbacks.js";
import { createMockHost, mockRuntimeConfig } from "./create-mock-host.js";
import { createWebWorkerPairingHostRuntime } from "./index.js";

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
    expect([first.id, second.id]).toEqual([0, 1]);
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
    const key = host.seedPreimage(new Uint8Array([4, 5, 6]));
    expect(key).toBeDefined();
    const found = await host.callbacks.preimage
      .lookupPreimage(key)
      [Symbol.asyncIterator]()
      .next();
    expect(found.value).toEqual(ok(new Uint8Array([4, 5, 6])));
  });

  it("preimage lookup misses on an unknown key", async () => {
    const host = createMockHost();
    host.seedPreimage(new Uint8Array([1, 2, 3]));
    const miss = await host.callbacks.preimage
      .lookupPreimage(new Uint8Array([9, 9, 9, 9, 9, 9, 9, 9]))
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
