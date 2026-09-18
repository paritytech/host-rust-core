import { afterEach, beforeEach, describe, expect, it } from "bun:test";

import { createMockHost } from "./create-mock-host.js";

type Listener = (event: { data?: string }) => void;

/**
 * A WebSocket stand-in the test drives by hand.
 *
 * Records every instance, so a test can assert how many sockets a run opened
 * and deliver a frame to one of them specifically -- which is the only way to
 * observe whether leases are isolated from each other.
 */
class FakeSocket {
  static instances: FakeSocket[] = [];

  readyState = 0;
  readonly sent: string[] = [];
  private readonly listeners = new Map<string, Listener[]>();

  constructor(readonly url: string) {
    FakeSocket.instances.push(this);
  }

  addEventListener(type: string, fn: Listener, options?: { once?: boolean }) {
    const wrapped: Listener = options?.once
      ? (event) => {
          this.remove(type, wrapped);
          fn(event);
        }
      : fn;
    this.listeners.set(type, [...(this.listeners.get(type) ?? []), wrapped]);
  }

  private remove(type: string, fn: Listener) {
    this.listeners.set(
      type,
      (this.listeners.get(type) ?? []).filter((each) => each !== fn),
    );
  }

  private emit(type: string, event: { data?: string }) {
    for (const fn of [...(this.listeners.get(type) ?? [])]) fn(event);
  }

  send(data: string) {
    this.sent.push(data);
  }

  close() {
    if (this.readyState === 3) return;
    this.readyState = 3;
    this.emit("close", {});
  }

  /** Drive the handshake to completion. */
  opened() {
    this.readyState = 1;
    this.emit("open", {});
  }

  /** Deliver an inbound frame to this socket only. */
  deliver(text: string) {
    this.emit("message", { data: text });
  }
}

/**
 * Resolve `pending` if it settles promptly, else null.
 *
 * Takes an already-started read rather than starting one, because a read that
 * parks stays parked: calling `next()` again would queue a second waiter and
 * the next frame would go to the first one, which makes a later assertion read
 * as a lost frame when nothing was lost.
 */
async function settledOrNull<T>(pending: Promise<T>): Promise<T | null> {
  return Promise.race([
    pending,
    new Promise<null>((resolve) => setTimeout(() => resolve(null), 10)),
  ]);
}

const PROXY = { chainProxies: [{ rpcUrl: "wss://node.test" }] };

describe("chain proxy", () => {
  // Save and restore: these suites share a process, so replacing a global
  // without putting it back breaks whichever file runs next.
  let original: typeof globalThis.WebSocket | undefined;

  beforeEach(() => {
    original = globalThis.WebSocket;
    FakeSocket.instances = [];
    globalThis.WebSocket = FakeSocket as unknown as typeof globalThis.WebSocket;
  });

  afterEach(() => {
    if (original) globalThis.WebSocket = original;
  });

  it("a lease does not observe another lease's inbound frames", async () => {
    const host = createMockHost(PROXY);
    const first = await host.callbacks.chain.connect(new Uint8Array(32));
    const second = await host.callbacks.chain.connect(new Uint8Array(32).fill(9));

    // Deliberately tolerant of there being only one socket: if the leases ever
    // share a transport again, this test must fail on the frame crossing over,
    // not on a socket count. Asserting the count here would hide the behaviour
    // behind an implementation detail.
    const socketA = FakeSocket.instances[0];
    const socketB = FakeSocket.instances[1] ?? FakeSocket.instances[0];

    // Both leases number their requests from 1, so an id says nothing about
    // which lease a frame belongs to. Isolation has to come from the transport.
    const frameA = '{"id":"truapi:1","result":"for-A"}';
    const frameB = '{"id":"truapi:1","result":"for-B"}';

    socketA.deliver(frameA);

    // B is waiting on its own socket. A's frame must not satisfy that wait.
    const readerB = second.responses()[Symbol.asyncIterator]();
    const pendingB = readerB.next();
    expect(await settledOrNull(pendingB)).toBeNull();

    const readerA = first.responses()[Symbol.asyncIterator]();
    expect(await readerA.next()).toEqual({ value: frameA, done: false });

    // The reverse direction, so the test cannot pass by ordering alone.
    const pendingA = readerA.next();
    socketB.deliver(frameB);
    expect(await settledOrNull(pendingA)).toBeNull();
    // The read that was parked all along resolves with its own socket's frame.
    expect(await pendingB).toEqual({ value: frameB, done: false });
  });

  it("each lease sends on its own socket", async () => {
    const host = createMockHost(PROXY);
    const first = await host.callbacks.chain.connect(new Uint8Array(32));
    const second = await host.callbacks.chain.connect(new Uint8Array(32).fill(9));
    const socketA = FakeSocket.instances[0];
    const socketB = FakeSocket.instances[1] ?? FakeSocket.instances[0];
    socketA.opened();
    socketB.opened();

    first.send("from-A");
    second.send("from-B");
    await Promise.resolve();
    await Promise.resolve();

    // A shared socket would carry both, so this reddens on the traffic before
    // the count below is reached.
    expect(socketA.sent).toEqual(["from-A"]);
    expect(socketB.sent).toEqual(["from-B"]);
    expect(FakeSocket.instances).toHaveLength(2);
    // Both are still recorded centrally, which is what getSentRpc reports.
    expect(host.sentRpc()).toEqual(["from-A", "from-B"]);
  });

  it("closing a lease closes its socket and leaves the other running", async () => {
    const host = createMockHost(PROXY);
    const first = await host.callbacks.chain.connect(new Uint8Array(32));
    const second = await host.callbacks.chain.connect(new Uint8Array(32).fill(9));
    const socketA = FakeSocket.instances[0];
    const socketB = FakeSocket.instances[1] ?? FakeSocket.instances[0];

    first.close();
    expect(socketA.readyState).toBe(3);
    expect(socketB.readyState).not.toBe(3);

    // The closed lease's reader ends rather than parking forever.
    const readerA = first.responses()[Symbol.asyncIterator]();
    expect(await readerA.next()).toEqual({ value: undefined, done: true });

    // The surviving lease still delivers.
    socketB.deliver("still-here");
    const readerB = second.responses()[Symbol.asyncIterator]();
    expect(await readerB.next()).toEqual({ value: "still-here", done: false });
  });

  it("a socket closed by the node ends the lease's reader", async () => {
    const host = createMockHost(PROXY);
    const connection = await host.callbacks.chain.connect(new Uint8Array(32));
    const reader = connection.responses()[Symbol.asyncIterator]();
    FakeSocket.instances[0].close();
    expect(await reader.next()).toEqual({ value: undefined, done: true });
  });
});
