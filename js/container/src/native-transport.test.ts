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
});
