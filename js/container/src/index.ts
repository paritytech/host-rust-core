// ============================================================================
// TrUAPI mode lockdown. Runs AFTER LocalhostBridgeBootstrap (native injects
// the bootstrap first), which publishes the bridge endpoint on
// window.__truapi_localhost and exposes __HOST_API_PORT__ /
// __HOST_WEBVIEW_MARK__.
// The bootstrap dials its WebSocket lazily (inside port.start()), so
// window.WebSocket must remain constructible for exactly the bridge URL.
//
// Hosts must inject this script into EVERY frame, not just the main frame. A
// realm without it has pristine fetch/WebSocket/RTCPeerConnection, and a
// product can reach one through any iframe path that skips
// `document.createElement` (innerHTML, document.write, createElementNS,
// srcdoc). Only the bootstrap is main-frame-only: a subframe with no bridge
// endpoint fails closed on every gate below.
// ============================================================================

// =============================================================================
// Isolation: Lock down globals so product scripts cannot access platform APIs.
// =============================================================================

import {
  freezeAndDelete,
  freezeCustom,
  freezeValue,
  reportLockdownFailures,
} from './freeze.js';
import { consumeWebRtcPolicy, installWebRtcPolicy } from './webrtc.js';
import { installFetchGate } from './network.js';
import { installXhrGate } from './xhr.js';
import { installWebSocketGate } from './websocket.js';
import { installMediaPolicy } from './media.js';
import { createPermissionAuthorization } from './network-transport.js';

const _authorize = createPermissionAuthorization(window);

const _bridgeUrl: string | undefined = (window as any).__truapi_localhost?.url;
const _webSocketBackend = (window as any).__truapi_websocket_connect__;
freezeAndDelete(window, '__truapi_websocket_connect__');
installWebSocketGate(window, _authorize.network, _bridgeUrl, _webSocketBackend);

installFetchGate(window, _authorize.network);
installXhrGate(window, _authorize.network);
installMediaPolicy(
  window,
  (window as any).__truapi_policy__?.mediaAllowed === false ? false : _authorize.media,
);

// --- Network: delete (no future permission path) ---
freezeAndDelete(window, 'EventSource');
freezeAndDelete(window, 'WebTransport');

freezeValue(navigator, 'sendBeacon', () => false);

// --- Storage ---
freezeAndDelete(window, 'indexedDB');
freezeAndDelete(window, 'caches');

// document.cookie — redefine as no-op getter/setter
freezeCustom(
  document,
  'cookie',
  { get: () => '', set: () => {} },
  (current) => current === '',
);

// --- Workers ---
freezeAndDelete(window, 'Worker');
freezeAndDelete(window, 'SharedWorker');

if (navigator.serviceWorker) {
  const _stubServiceWorker = Object.freeze({
    register: () => { throw new Error('ServiceWorker is not available'); },
  });
  freezeCustom(
    navigator,
    'serviceWorker',
    { value: _stubServiceWorker, writable: false },
    (current) => current === _stubServiceWorker,
  );
}

// --- DOM: block iframe creation ---
const _createElement = document.createElement.bind(document);
freezeValue(document, 'createElement', (tagName: string, options?: ElementCreationOptions) => {
  if (tagName.toLowerCase() === 'iframe') {
    throw new Error('iframe creation is not allowed');
  }
  return _createElement(tagName, options);
});

// Hosts without WebRTC support can disable it regardless of product consent.
installWebRtcPolicy(
  window,
  consumeWebRtcPolicy(window) === false ? false : _authorize.webRtc,
);

// --- Report: every lock above has been attempted, so a failure can throw ---
// A lock that did not take is a hole in the sandbox. Reporting last means the
// throw costs no coverage, and it means the host learns rather than serving
// products into a realm it believes is closed.
reportLockdownFailures();

export {};
