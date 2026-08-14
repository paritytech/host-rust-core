import { afterEach, describe, expect, it } from 'bun:test';

import { createAndroidBridge } from './android-bridge.js';
import { HANDLER_NAME } from './bridge-contract.js';
import type { NativeTransport } from './native-transport.js';

type Call = { functionName: string; argsJson: string };
type FakeWindow = Record<string, unknown> & {
  Android?: { call(functionName: string, argsJson: string): string };
};

/** Installs a fake `window` exposing the Android JavascriptInterface. */
function installFakeWindow() {
  const calls: Call[] = [];
  const android = {
    call: (functionName: string, argsJson: string) => {
      calls.push({ functionName, argsJson });
      return '';
    },
  };
  const win: FakeWindow = { Android: android };
  const prior = globalThis.window;
  globalThis.window = win as unknown as Window & typeof globalThis;
  return { win, calls, prior };
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

function dispatcher(): (id: string, payload: string) => void {
  return (globalThis.window as unknown as {
    __container_callback__: (id: string, payload: string) => void;
  }).__container_callback__;
}

describe('createAndroidBridge', () => {
  it('returns a transport when Android.call is present, undefined otherwise', () => {
    const { win } = fresh();
    expect(createAndroidBridge()).toBeDefined();

    win.Android = { call: undefined as unknown as () => string };
    expect(createAndroidBridge()).toBeUndefined();

    delete win.Android;
    expect(createAndroidBridge()).toBeUndefined();
  });

  it('routes calls through Android.call(HANDLER_NAME, json) and resolves replies', async () => {
    const { calls } = fresh();
    const transport = createAndroidBridge() as NativeTransport;

    const call = transport.callNative('someOtherNativeApi', { a: 1 });
    expect(calls[0].functionName).toBe(HANDLER_NAME);
    const sent = JSON.parse(calls[0].argsJson);
    expect(sent.method).toBe('someOtherNativeApi');
    expect(sent.params).toEqual({ a: 1 });

    dispatcher()(sent.id, JSON.stringify({ value: 42 }));
    expect(await call).toBe(42);
  });

  it('uses the captured Android.call even after window.Android is replaced', () => {
    const { win, calls } = fresh();
    const transport = createAndroidBridge() as NativeTransport;

    // Product swaps in a spy after init.
    const spied: Call[] = [];
    win.Android = {
      call: (functionName: string, argsJson: string) => {
        spied.push({ functionName, argsJson });
        return '';
      },
    };

    void transport.callNative('m', {});

    expect(spied).toHaveLength(0);
    expect(calls).toHaveLength(1);
  });

  it('freezes the reply callback against reassignment and deletion', () => {
    const { win } = fresh();
    createAndroidBridge();

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
    expect(threw || win.__container_callback__ === original).toBe(true);
  });
});
