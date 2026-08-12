// =============================================================================
// Platform-agnostic, permission-gated RTCPeerConnection.
//
// The manager subclasses the native RTCPeerConnection and gates the async
// methods that initiate network activity (SDP exchange and ICE). A peer
// connection is inert until one of these is called, so the constructor is
// intentionally not gated. Access is requested once per connection and the
// decision is cached; a denial closes the connection and throws.
//
// `createWebRtcAccessRequester` adapts a NativeTransport into the requester the
// manager expects; any platform that exposes a transport reuses both.
// =============================================================================

import type { NativeTransport } from './native-transport.js';

/**
 * Requests app-level WebRTC access from the host. Resolves `true` when access
 * is granted for this connection, `false` on denial.
 */
export type WebRtcAccessRequester = () => Promise<boolean>;

/**
 * Builds a WebRTC access requester over a native transport. Platform-agnostic:
 * any host that exposes a `NativeTransport` reuses this to gate WebRTC through
 * the `allowWebRtcAccess` contract method.
 */
export function createWebRtcAccessRequester(
  transport: NativeTransport,
): WebRtcAccessRequester {
  return () =>
    transport.callNative('allowWebRtcAccess', {}).then(
      (reply) =>
        typeof reply === 'object' &&
        reply !== null &&
        (reply as { allowed?: unknown }).allowed === true,
    );
}

/** Async methods that initiate network activity and must be gated. */
type GatedMethodName =
  | 'createOffer'
  | 'createAnswer'
  | 'setLocalDescription'
  | 'setRemoteDescription'
  | 'addIceCandidate';

const GATED_METHODS: readonly GatedMethodName[] = [
  'createOffer',
  'createAnswer',
  'setLocalDescription',
  'setRemoteDescription',
  'addIceCandidate',
];

/** A native async peer-connection method, called generically for gating. */
type AsyncPeerMethod = (
  this: RTCPeerConnection,
  ...args: unknown[]
) => Promise<unknown>;

/**
 * Wraps a native RTCPeerConnection class in a permission gate. Install
 * `connectionClass` as the drop-in replacement for `window.RTCPeerConnection`.
 */
export class WebRtcManager {
  /** Gated RTCPeerConnection subclass to install in place of the native one. */
  readonly connectionClass: typeof RTCPeerConnection;

  constructor(
    nativeConnectionClass: typeof RTCPeerConnection,
    requestAccess: WebRtcAccessRequester,
  ) {
    // One in-flight/cached decision per connection instance.
    const decisions = new WeakMap<object, Promise<boolean>>();

    const ensureAllowed = (connection: RTCPeerConnection): Promise<void> => {
      let decision = decisions.get(connection);
      if (decision === undefined) {
        decision = requestAccess();
        decisions.set(connection, decision);
      }
      return decision.then((allowed) => {
        if (!allowed) {
          connection.close();
          throw new TypeError('WebRTC access is not allowed');
        }
      });
    };

    class GatedRTCPeerConnection extends nativeConnectionClass {}

    const proto = GatedRTCPeerConnection.prototype;
    for (const name of GATED_METHODS) {
      // The native class' overloaded DOM signatures cannot be forwarded
      // through a uniform wrapper without losing overloads, so read the method
      // once as a generic async function and apply it after the gate resolves.
      const nativeMethod = nativeConnectionClass.prototype[
        name
      ] as unknown as AsyncPeerMethod;
      Object.defineProperty(proto, name, {
        configurable: true,
        writable: true,
        value: async function (
          this: RTCPeerConnection,
          ...args: unknown[]
        ): Promise<unknown> {
          await ensureAllowed(this);
          return nativeMethod.apply(this, args);
        },
      });
    }

    this.connectionClass = GatedRTCPeerConnection;
  }
}
