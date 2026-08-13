// =============================================================================
// Platform-agnostic, permission-gated RTCPeerConnection.
//
// The manager patches the async methods that initiate network activity (SDP
// exchange and ICE) directly onto the native RTCPeerConnection prototype, as
// non-configurable / non-writable properties, and exposes the native class
// itself as `connectionClass`.
//
// Patching in place — rather than subclassing — is required for the same-realm
// threat model: a product script must not be able to reach an ungated method.
// A subclass leaves three holes (a deletable shadow, the ungated parent
// prototype, and the native constructor recoverable via the subclass
// `[[Prototype]]`); an in-place patch has none — the sole method on the chain is
// the gated one, it cannot be deleted or overwritten, and there is no native
// twin to construct.
//
// A peer connection is inert until a gated method touches the network, so the
// constructor is not gated. Access is requested once per connection and the
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
 * Gates a native RTCPeerConnection class in place. Install `connectionClass`
 * (the same native class, now patched) as `window.RTCPeerConnection`.
 */
export class WebRtcManager {
  /** The native RTCPeerConnection class, patched in place with the gate. */
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

    const proto = nativeConnectionClass.prototype;
    for (const name of GATED_METHODS) {
      // Capture the native method, then replace it on the native prototype as a
      // non-configurable / non-writable data property so product code cannot
      // delete, overwrite, or walk past the gate. The overloaded DOM signatures
      // can't be forwarded through a typed wrapper, so treat it as a generic
      // async function.
      const nativeMethod = proto[name] as unknown as AsyncPeerMethod;
      Object.defineProperty(proto, name, {
        configurable: false,
        writable: false,
        enumerable: true,
        value: async function (
          this: RTCPeerConnection,
          ...args: unknown[]
        ): Promise<unknown> {
          await ensureAllowed(this);
          return nativeMethod.apply(this, args);
        },
      });
    }

    this.connectionClass = nativeConnectionClass;
  }
}
