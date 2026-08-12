import { afterEach, describe, expect, it } from 'bun:test';

import { HANDLER_NAME } from './bridge-contract.js';
import { createNativeBridge } from './native-bridge.js';

type FakeWindow = Record<string, unknown> & {
  webkit?: { messageHandlers?: Record<string, { postMessage(m: unknown): void } | undefined> };
  Android?: { call(functionName: string, argsJson: string): string };
};

/** Installs a fake `window` with the requested native channels present. */
function installFakeWindow(opts: { ios?: boolean; android?: boolean }) {
  const iosPosts: string[] = [];
  const androidCalls: string[] = [];
  const win: FakeWindow = {};
  if (opts.ios) {
    win.webkit = {
      messageHandlers: {
        [HANDLER_NAME]: { postMessage: (m: unknown) => iosPosts.push(m as string) },
      },
    };
  }
  if (opts.android) {
    win.Android = {
      call: (_functionName: string, argsJson: string) => {
        androidCalls.push(argsJson);
        return '';
      },
    };
  }
  const prior = globalThis.window;
  globalThis.window = win as unknown as Window & typeof globalThis;
  return { iosPosts, androidCalls, prior };
}

let ctx: ReturnType<typeof installFakeWindow> | undefined;

afterEach(() => {
  if (ctx?.prior === undefined) {
    delete (globalThis as { window?: unknown }).window;
  } else {
    globalThis.window = ctx.prior;
  }
  ctx = undefined;
});

describe('createNativeBridge', () => {
  it('selects the iOS bridge when present', () => {
    ctx = installFakeWindow({ ios: true });
    const transport = createNativeBridge();
    expect(transport).toBeDefined();

    void transport?.callNative('m', {});
    expect(ctx.iosPosts).toHaveLength(1);
  });

  it('falls back to the Android bridge when iOS is absent', () => {
    ctx = installFakeWindow({ android: true });
    const transport = createNativeBridge();
    expect(transport).toBeDefined();

    void transport?.callNative('m', {});
    expect(ctx.androidCalls).toHaveLength(1);
  });

  it('prefers iOS when both are present', () => {
    ctx = installFakeWindow({ ios: true, android: true });
    const transport = createNativeBridge();

    void transport?.callNative('m', {});
    expect(ctx.iosPosts).toHaveLength(1);
    expect(ctx.androidCalls).toHaveLength(0);
  });

  it('returns undefined when neither host is present', () => {
    ctx = installFakeWindow({});
    expect(createNativeBridge()).toBeUndefined();
  });
});
