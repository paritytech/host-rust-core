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

import { installContainer } from './container.js';
import { createPermissionAuthorization } from './network-transport.js';

installContainer(createPermissionAuthorization(window));
