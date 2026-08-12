import { describe, expect, it, mock } from 'bun:test';

import type { NativeTransport } from './native-transport.js';
import { WebRtcManager, createWebRtcAccessRequester } from './webrtc-manager.js';

/** Mock transport recording calls and returning a canned reply. */
function mockTransport(reply: unknown) {
  const calls: Array<{ method: string; params: unknown }> = [];
  const transport: NativeTransport = {
    callNative(method, params) {
      calls.push({ method, params });
      return Promise.resolve(reply);
    },
    dispatch() {
      /* unused by the requester */
    },
  };
  return { transport, calls };
}

/**
 * Minimal stand-in for a native RTCPeerConnection. Each gated method records
 * its name so tests can assert delegation to the native implementation, and
 * `close()` flips `closed` so denial handling is observable.
 */
function makeNativeClass() {
  const calls: string[] = [];
  class FakeRTCPeerConnection {
    closed = false;

    createOffer(): Promise<RTCSessionDescriptionInit> {
      calls.push('createOffer');
      return Promise.resolve({ type: 'offer', sdp: 'x' });
    }
    createAnswer(): Promise<RTCSessionDescriptionInit> {
      calls.push('createAnswer');
      return Promise.resolve({ type: 'answer', sdp: 'y' });
    }
    setLocalDescription(): Promise<void> {
      calls.push('setLocalDescription');
      return Promise.resolve();
    }
    setRemoteDescription(): Promise<void> {
      calls.push('setRemoteDescription');
      return Promise.resolve();
    }
    addIceCandidate(): Promise<void> {
      calls.push('addIceCandidate');
      return Promise.resolve();
    }
    close(): void {
      this.closed = true;
      calls.push('close');
    }
  }
  return {
    NativeClass: FakeRTCPeerConnection as unknown as typeof RTCPeerConnection,
    calls,
  };
}

const GATED_METHODS = [
  'createOffer',
  'createAnswer',
  'setLocalDescription',
  'setRemoteDescription',
  'addIceCandidate',
] as const;

describe('WebRtcManager', () => {
  it('delegates each gated method to the native super method when granted', async () => {
    for (const method of GATED_METHODS) {
      const { NativeClass, calls } = makeNativeClass();
      const requestAccess = mock(() => Promise.resolve(true));
      const Gated = new WebRtcManager(NativeClass, requestAccess).connectionClass;

      const pc = new Gated();
      const result = await (
        pc as unknown as Record<string, () => Promise<unknown>>
      )[method]();

      expect(requestAccess).toHaveBeenCalledTimes(1);
      expect(calls).toContain(method);
      if (method === 'createOffer') {
        expect(result).toEqual({ type: 'offer', sdp: 'x' });
      }
    }
  });

  it('closes the connection and throws TypeError when denied', async () => {
    const { NativeClass, calls } = makeNativeClass();
    const requestAccess = mock(() => Promise.resolve(false));
    const Gated = new WebRtcManager(NativeClass, requestAccess).connectionClass;

    const pc = new Gated();
    await expect(pc.createOffer()).rejects.toThrow(
      new TypeError('WebRTC access is not allowed'),
    );
    expect((pc as unknown as { closed: boolean }).closed).toBe(true);
    expect(calls).toContain('close');
    expect(calls).not.toContain('createOffer');
  });

  it('requests permission exactly once per connection', async () => {
    const { NativeClass } = makeNativeClass();
    const requestAccess = mock(() => Promise.resolve(true));
    const Gated = new WebRtcManager(NativeClass, requestAccess).connectionClass;

    const pc = new Gated();
    await pc.createOffer();
    await pc.setLocalDescription({ type: 'offer', sdp: 'x' });
    await pc.createAnswer();

    expect(requestAccess).toHaveBeenCalledTimes(1);
  });

  it('shares a single in-flight request across concurrent gated calls', async () => {
    const { NativeClass } = makeNativeClass();
    const requestAccess = mock(() => Promise.resolve(true));
    const Gated = new WebRtcManager(NativeClass, requestAccess).connectionClass;

    const pc = new Gated();
    await Promise.all([pc.createOffer(), pc.createAnswer()]);

    expect(requestAccess).toHaveBeenCalledTimes(1);
  });

  it('requests permission again for a separate connection', async () => {
    const { NativeClass } = makeNativeClass();
    const requestAccess = mock(() => Promise.resolve(true));
    const Gated = new WebRtcManager(NativeClass, requestAccess).connectionClass;

    await new Gated().createOffer();
    await new Gated().createOffer();

    expect(requestAccess).toHaveBeenCalledTimes(2);
  });
});

describe('createWebRtcAccessRequester', () => {
  it('calls the allowWebRtcAccess method and resolves true when granted', async () => {
    const { transport, calls } = mockTransport({ allowed: true });
    const request = createWebRtcAccessRequester(transport);

    expect(await request()).toBe(true);
    expect(calls).toEqual([{ method: 'allowWebRtcAccess', params: {} }]);
  });

  it('resolves false when denied', async () => {
    const { transport } = mockTransport({ allowed: false });
    expect(await createWebRtcAccessRequester(transport)()).toBe(false);
  });

  it('resolves false for a malformed or missing reply', async () => {
    expect(await createWebRtcAccessRequester(mockTransport(null).transport)()).toBe(false);
    expect(await createWebRtcAccessRequester(mockTransport('nope').transport)()).toBe(false);
    expect(await createWebRtcAccessRequester(mockTransport({}).transport)()).toBe(false);
  });
});
