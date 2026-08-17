import { describe, expect, it } from 'bun:test';

import { createNativeTransport } from './native-transport.js';

/** Captures outbound envelopes so a test can reply to the right request id. */
function makeSender() {
  const sent: Array<{ type: string; id: string; method: string; params: unknown }> = [];
  return {
    sent,
    send(message: string) {
      sent.push(JSON.parse(message));
    },
  };
}

describe('createNativeTransport', () => {
  it('resolves with the reply value', async () => {
    const sender = makeSender();
    const transport = createNativeTransport(sender.send);

    const call = transport.callNative('allowWebRtcAccess', {});
    const { id } = sender.sent[0];
    transport.dispatch(id, JSON.stringify({ value: { allowed: true } }));

    expect(await call).toEqual({ allowed: true });
  });

  it('sends a well-formed request envelope', () => {
    const sender = makeSender();
    const transport = createNativeTransport(sender.send);

    void transport.callNative('allowWebRtcAccess', { a: 1 });

    expect(sender.sent[0].type).toBe('request');
    expect(sender.sent[0].method).toBe('allowWebRtcAccess');
    expect(sender.sent[0].params).toEqual({ a: 1 });
    expect(typeof sender.sent[0].id).toBe('string');
  });

  it('rejects with the error code preserved', async () => {
    const sender = makeSender();
    const transport = createNativeTransport(sender.send);

    const call = transport.callNative('allowWebRtcAccess', {});
    const { id } = sender.sent[0];
    transport.dispatch(
      id,
      JSON.stringify({ error: { code: 'denied', message: 'nope' } }),
    );

    await expect(call).rejects.toMatchObject({ code: 'denied', message: 'nope' });
  });

  it('tolerates a string error', async () => {
    const sender = makeSender();
    const transport = createNativeTransport(sender.send);

    const call = transport.callNative('allowWebRtcAccess', {});
    transport.dispatch(sender.sent[0].id, JSON.stringify({ error: 'boom' }));

    await expect(call).rejects.toMatchObject({ code: 'boom' });
  });

  it('routes concurrent in-flight calls to their matching ids', async () => {
    const sender = makeSender();
    const transport = createNativeTransport(sender.send);

    const first = transport.callNative('m1', {});
    const second = transport.callNative('m2', {});
    const [id1, id2] = [sender.sent[0].id, sender.sent[1].id];

    // Reply out of order.
    transport.dispatch(id2, JSON.stringify({ value: 2 }));
    transport.dispatch(id1, JSON.stringify({ value: 1 }));

    expect(await first).toBe(1);
    expect(await second).toBe(2);
  });

  it('ignores unknown and stale ids', async () => {
    const sender = makeSender();
    const transport = createNativeTransport(sender.send);

    const call = transport.callNative('m', {});
    const { id } = sender.sent[0];

    // Unknown id: no throw, no effect.
    expect(() => transport.dispatch('deadbeef', JSON.stringify({ value: 1 }))).not.toThrow();

    transport.dispatch(id, JSON.stringify({ value: 'ok' }));
    expect(await call).toBe('ok');

    // Stale id: the entry is gone; a second dispatch is a no-op.
    expect(() => transport.dispatch(id, JSON.stringify({ value: 'again' }))).not.toThrow();
  });

  // The RNG and serializer on the id's path are captured at module init, so a
  // product overriding the globals afterward cannot make ids predictable or
  // observe an outbound id.
  it('generates ids from a captured RNG even if crypto.getRandomValues is poisoned', () => {
    const sender = makeSender();
    const transport = createNativeTransport(sender.send);

    const proto = Object.getPrototypeOf(crypto) as {
      getRandomValues: <T extends ArrayBufferView | null>(a: T) => T;
    };
    const real = proto.getRandomValues;
    proto.getRandomValues = (<T extends ArrayBufferView | null>(a: T): T => {
      if (a instanceof Uint8Array) a.fill(0);
      return a;
    });
    try {
      void transport.callNative('m', {});
    } finally {
      proto.getRandomValues = real;
    }

    const id = sender.sent[0].id;
    expect(id).not.toBe('0'.repeat(32)); // not the poisoned deterministic value
    expect(id).toMatch(/^[0-9a-f]{32}$/);
  });

  it('serializes with a captured JSON.stringify even if the global is poisoned', () => {
    const sender = makeSender();
    const transport = createNativeTransport(sender.send);

    const realStringify = JSON.stringify;
    const seen: unknown[] = [];
    JSON.stringify = ((value: unknown, ...rest: unknown[]) => {
      seen.push(value);
      return (realStringify as (...a: unknown[]) => string)(value, ...rest);
    }) as typeof JSON.stringify;
    try {
      void transport.callNative('m', {});
    } finally {
      JSON.stringify = realStringify;
    }

    // The transport used the captured serializer, so the poison never saw the id.
    expect(seen).toHaveLength(0);
    expect(sender.sent[0].id).toMatch(/^[0-9a-f]{32}$/);
  });

  it('encodes ids without poisonable intrinsics (toString/padStart override)', () => {
    const sender = makeSender();
    const transport = createNativeTransport(sender.send);

    const realToString = Number.prototype.toString;
    const realPadStart = String.prototype.padStart;
    // With the old `byte.toString(16).padStart(2,'0')` encoding these would make
    // every id `ff…ff`.
    Number.prototype.toString = () => 'ff';
    String.prototype.padStart = function () {
      return 'ff';
    };
    try {
      void transport.callNative('m', {});
    } finally {
      Number.prototype.toString = realToString;
      String.prototype.padStart = realPadStart;
    }

    const id = sender.sent[0].id;
    expect(id).not.toBe('ff'.repeat(16));
    expect(id).toMatch(/^[0-9a-f]{32}$/);
  });

  it('does not expose the id to a poisoned Object.prototype.toJSON', () => {
    const sender = makeSender();
    const transport = createNativeTransport(sender.send);

    const proto = Object.prototype as { toJSON?: unknown };
    const had = 'toJSON' in proto;
    const real = proto.toJSON;
    const seen: unknown[] = [];
    proto.toJSON = function (this: unknown) {
      seen.push(this); // records every object stringify calls toJSON on
      return this;
    };
    try {
      void transport.callNative('allowWebRtcAccess', {});
    } finally {
      if (had) proto.toJSON = real;
      else delete proto.toJSON;
    }

    // The envelope carries the id but has a null prototype, so its toJSON was
    // never invoked — no object with an `id` reached the poisoned toJSON.
    const leakedId = seen.some(
      (v) => typeof v === 'object' && v !== null && 'id' in v,
    );
    expect(leakedId).toBe(false);
    expect(sender.sent[0].id).toMatch(/^[0-9a-f]{32}$/);
  });
});
