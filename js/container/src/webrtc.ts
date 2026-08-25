// WebRTC egress policy (RFC 0002 `RemotePermission::WebRtc`).
//
// A peer connection reaches an arbitrary host without touching any layer the
// host can observe: ICE is UDP to whatever STUN/TURN server the product names,
// so no content rule list, no `shouldInterceptRequest`, and no CSP directive
// sees it. That makes this the one egress path with no out-of-realm enforcement
// point on any host, and the reason the decision has to be enforced in-realm.
//
// The decision is resolved by the host *before* this realm exists and arrives
// as a plain boolean. That is deliberate and load-bearing: an asynchronous
// permission request from inside the product's realm is forgeable, because the
// product can hook whatever primitive the pending-request bookkeeping touches
// and resolve it itself:
//
//     const realSet = Map.prototype.set;
//     let steal;
//     Map.prototype.set = function (id, e) { steal = e; return realSet.call(this, id, e); };
//     new RTCPeerConnection().createOffer().catch(() => {});
//     queueMicrotask(() => steal.resolve({ allowed: true }));
//
// With a boolean settled up front there is no pending state to steal, and a
// denial needs no gate at all: removing the constructor leaves no reachable
// prototype and no recoverable native class, so there is nothing to escape
// from. The cost is that a fresh grant only takes effect on the next load.

/* eslint-disable @typescript-eslint/no-explicit-any */

import { freezeAndDelete } from './freeze.js';

/**
 * Global the host's bootstrap publishes with the pre-resolved decision. Read
 * once and removed, so the product realm never carries a knob that looks
 * negotiable.
 */
export const POLICY_GLOBAL = '__truapi_policy__';

/**
 * Apply the WebRTC decision to `win`.
 *
 * Anything other than an explicit `true` denies: an absent policy global means
 * a host that never resolved a decision — including any subframe, which gets no
 * bootstrap — and that must fail closed.
 */
export function installWebRtcPolicy(win: any, allowed: unknown): void {
  if (allowed === true) {
    return;
  }
  freezeAndDelete(win, 'RTCPeerConnection');
  // Vendor-prefixed aliases are separate constructors, not views of the
  // standard one, so leaving either behind reopens the path outright.
  freezeAndDelete(win, 'webkitRTCPeerConnection');
  freezeAndDelete(win, 'mozRTCPeerConnection');
}

/** Read the decision the bootstrap published, then remove the global. */
export function consumeWebRtcPolicy(win: any): unknown {
  const allowed = win?.[POLICY_GLOBAL]?.webRtcAllowed;
  freezeAndDelete(win, POLICY_GLOBAL);
  return allowed;
}
