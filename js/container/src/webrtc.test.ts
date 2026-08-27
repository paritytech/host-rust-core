import { describe, expect, it } from 'bun:test';

import { POLICY_GLOBAL, consumeWebRtcPolicy, installWebRtcPolicy } from './webrtc.js';

/* eslint-disable @typescript-eslint/no-explicit-any */

/** Stand-in for the native constructor, so a test can tell it apart. */
class NativePeerConnection {
  createOffer() { return Promise.resolve({ sdp: 'native', type: 'offer' }); }
  createAnswer() { return Promise.resolve({ sdp: 'native', type: 'answer' }); }
  setLocalDescription() { return Promise.resolve(); }
  setRemoteDescription() { return Promise.resolve(); }
  addIceCandidate() { return Promise.resolve(); }
  createDataChannel() { return { send() {} }; }
}

function realm(policy?: unknown): any {
  const win: any = {
    RTCPeerConnection: NativePeerConnection,
    webkitRTCPeerConnection: NativePeerConnection,
  };
  if (policy !== undefined) {
    win[POLICY_GLOBAL] = policy;
  }
  return win;
}

function denied(): any {
  const win = realm({ webRtcAllowed: false });
  installWebRtcPolicy(win, consumeWebRtcPolicy(win));
  return win;
}

describe('the decision', () => {
  it('leaves the constructor in place when granted', () => {
    const win = realm({ webRtcAllowed: true });
    installWebRtcPolicy(win, consumeWebRtcPolicy(win));
    expect(win.RTCPeerConnection).toBe(NativePeerConnection);
  });

  it('removes the constructor when denied', () => {
    expect(denied().RTCPeerConnection).toBeUndefined();
  });

  it('removes vendor-prefixed aliases too', () => {
    // A separate constructor, not a view of the standard one: leaving it
    // behind would reopen the path outright.
    expect(denied().webkitRTCPeerConnection).toBeUndefined();
  });

  it('consumes the policy global so the realm does not carry it', () => {
    const win = realm({ webRtcAllowed: true });
    consumeWebRtcPolicy(win);
    expect(win[POLICY_GLOBAL]).toBeUndefined();
  });
});

describe('fails closed', () => {
  // A subframe gets the container but no bootstrap, so it has no policy at all.
  it('with no policy global', () => {
    const win = realm();
    installWebRtcPolicy(win, consumeWebRtcPolicy(win));
    expect(win.RTCPeerConnection).toBeUndefined();
  });

  // Only an explicit `true` may grant, so a truthy-but-not-true value — the
  // shape a sloppy host or a tampered global would produce — must still deny.
  const nonGrants: Array<[string, unknown]> = [
    ['a truthy string', 'yes'],
    ['a truthy number', 1],
    ['null', null],
    ['undefined', undefined],
    ['an empty policy object', {}],
  ];
  for (const [label, value] of nonGrants) {
    it(`on ${label}`, () => {
      const win = realm({ webRtcAllowed: value });
      installWebRtcPolicy(win, consumeWebRtcPolicy(win));
      expect(win.RTCPeerConnection).toBeUndefined();
    });
  }
});

// The four escapes that killed the gate in truapi#379. Each recovered a working
// peer connection from a *subclass*-based gate, because a subclass leaves the
// native class reachable. Each route below must yield no connection that can
// produce an offer — that is the property, not "some property access throws".
//
// `attempt` runs a route and reports what a product would actually get: an
// offer means the route won.
async function attempt(route: () => any): Promise<string | null> {
  try {
    const offer = await route().createOffer();
    return offer?.sdp ?? null;
  } catch {
    return null;
  }
}

describe('resists the #379 escapes when denied', () => {
  it('yields no connection by deleting a shadowing prototype method', async () => {
    const win = denied();
    expect(
      await attempt(() => {
        delete win.RTCPeerConnection.prototype.createOffer;
        return new win.RTCPeerConnection();
      }),
    ).toBeNull();
  });

  it('yields no connection by reaching the parent prototype', async () => {
    const win = denied();
    expect(
      await attempt(() => {
        const pc = new win.RTCPeerConnection();
        const parent = Object.getPrototypeOf(Object.getPrototypeOf(pc));
        return { createOffer: () => parent.createOffer.call(pc) };
      }),
    ).toBeNull();
  });

  it('yields no connection by recovering the class [[Prototype]]', async () => {
    const win = denied();
    expect(
      await attempt(() => new (Object.getPrototypeOf(win.RTCPeerConnection))()),
    ).toBeNull();
  });

  it('has no pending request whose resolver could be stolen', () => {
    // The decisive #379 break: hook the primitive the pending-request
    // bookkeeping used, steal the `{resolve, reject}` pair, and forge a grant.
    // A settled boolean has no such bookkeeping, so there is nothing to hand a
    // product.
    const win = realm({ webRtcAllowed: false });
    const realSet = Map.prototype.set;
    let stolen: unknown;
    Map.prototype.set = function (this: Map<unknown, unknown>, key: unknown, value: unknown) {
      stolen = value;
      return realSet.call(this, key, value);
    };
    try {
      installWebRtcPolicy(win, consumeWebRtcPolicy(win));
    } finally {
      Map.prototype.set = realSet;
    }
    expect(stolen).toBeUndefined();
    expect(win.RTCPeerConnection).toBeUndefined();
  });

  it('cannot be restored by redefining the property', () => {
    const win = denied();
    expect(() =>
      Object.defineProperty(win, 'RTCPeerConnection', { value: NativePeerConnection }),
    ).toThrow();
    expect(win.RTCPeerConnection).toBeUndefined();
  });

  it('ignores a plain assignment', () => {
    const win = denied();
    win.RTCPeerConnection = NativePeerConnection;
    expect(win.RTCPeerConnection).toBeUndefined();
  });
});

// Guard the guard: the same routes must succeed against the subclass design, or
// the tests above would pass for a gate that does nothing.
describe('the escape routes are real against a subclass gate', () => {
  function subclassGated(): any {
    const Gated = class extends NativePeerConnection {
      override createOffer(): any {
        return Promise.reject(new TypeError('WebRTC access is not allowed'));
      }
    };
    return { RTCPeerConnection: Gated };
  }

  it('the parent prototype still answers', async () => {
    const win = subclassGated();
    const pc = new win.RTCPeerConnection();
    const parent = Object.getPrototypeOf(Object.getPrototypeOf(pc));
    expect(await parent.createOffer.call(pc)).toMatchObject({ sdp: 'native' });
  });

  it('the class [[Prototype]] is the native constructor', async () => {
    const win = subclassGated();
    const Native = Object.getPrototypeOf(win.RTCPeerConnection);
    expect(await new Native().createOffer()).toMatchObject({ sdp: 'native' });
  });
});
