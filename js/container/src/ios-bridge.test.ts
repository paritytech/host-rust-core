import { afterEach, describe, expect, it } from 'bun:test';

import { HANDLER_NAME } from './bridge-contract.js';
import { createIOSBridge } from './ios-bridge.js';
import type { NativeTransport } from './native-transport.js';

type Posted = string[];
type FakeWindow = Record<string, unknown> & {
  webkit?: { messageHandlers?: Record<string, { postMessage(m: unknown): void } | undefined> };
};

/** Installs a fake `window` exposing the native container message handler. */
function installFakeWindow() {
  const posted: Posted = [];
  const handler = {
    postMessage: (message: unknown) => {
      posted.push(message as string);
    },
  };
  const win: FakeWindow = {
    webkit: { messageHandlers: { [HANDLER_NAME]: handler } },
  };
  const prior = globalThis.window;
  globalThis.window = win as unknown as Window & typeof globalThis;
  return { win, posted, prior };
}

let ctx: ReturnType<typeof installFakeWindow> | undefined;

function fresh() {
  ctx = installFakeWindow();
  return ctx;
}

afterEach(() => {
  if (ctx?.prior === undefined) {
    delete (globalThis as { window?: unknown }).window;
  } else {
    globalThis.window = ctx.prior;
  }
  ctx = undefined;
});

function idOf(message: string): string {
  return JSON.parse(message).id;
}

/** Reads the frozen reply dispatcher installed on the fake window. */
function dispatcher(): (id: string, payload: string) => void {
  return (globalThis.window as unknown as {
    __container_callback__: (id: string, payload: string) => void;
  }).__container_callback__;
}

describe('createIOSBridge', () => {
  it('returns a transport when the handler is present, undefined otherwise', () => {
    const { win } = fresh();
    expect(createIOSBridge()).toBeDefined();

    win.webkit = { messageHandlers: {} };
    expect(createIOSBridge()).toBeUndefined();

    delete win.webkit;
    expect(createIOSBridge()).toBeUndefined();
  });

  it('exposes a reusable transport for arbitrary native methods', async () => {
    const { posted } = fresh();
    const transport = createIOSBridge() as NativeTransport;

    const call = transport.callNative('someOtherNativeApi', { a: 1 });
    const sent = JSON.parse(posted[0]);
    expect(sent.method).toBe('someOtherNativeApi');
    expect(sent.params).toEqual({ a: 1 });

    dispatcher()(sent.id, JSON.stringify({ value: 42 }));
    expect(await call).toBe(42);
  });

  it('emits unguessable, unique, non-sequential ids', () => {
    const { posted } = fresh();
    const transport = createIOSBridge() as NativeTransport;

    void transport.callNative('m', {});
    void transport.callNative('m', {});
    void transport.callNative('m', {});

    const ids = posted.map(idOf);
    expect(new Set(ids).size).toBe(3);
    for (const id of ids) {
      expect(id).toMatch(/^[0-9a-f]{32}$/);
    }
    // Not a sequential counter like r0/r1/r2.
    expect(ids).not.toEqual(['r0', 'r1', 'r2']);
  });

  it('uses the captured postMessage even after messageHandlers is replaced', () => {
    const { win, posted } = fresh();
    const transport = createIOSBridge() as NativeTransport;

    // Product swaps in a spy after init.
    const spied: string[] = [];
    win.webkit = {
      messageHandlers: {
        [HANDLER_NAME]: { postMessage: (m: unknown) => spied.push(m as string) },
      },
    };

    void transport.callNative('m', {});

    expect(spied).toHaveLength(0);
    expect(posted).toHaveLength(1);
  });

  it('freezes the reply callback against reassignment and deletion', () => {
    const { win } = fresh();
    createIOSBridge();

    const original = win.__container_callback__;
    expect(typeof original).toBe('function');

    win.__container_callback__ = () => 'evil';
    expect(win.__container_callback__).toBe(original);

    let threw = false;
    try {
      delete win.__container_callback__;
    } catch {
      threw = true;
    }
    expect(win.__container_callback__).toBe(original);
    // Non-configurable delete either throws or returns false; either way the
    // callback must survive.
    expect(threw || win.__container_callback__ === original).toBe(true);
  });
});
