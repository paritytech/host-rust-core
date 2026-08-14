// ============================================================================
// iOS lockdown entry point. Runs AFTER LocalhostBridgeBootstrap (native injects
// the bootstrap first), which publishes the bridge endpoint on
// window.__truapi_localhost. The bootstrap dials its WebSocket lazily, so
// window.WebSocket must remain constructible for exactly the bridge URL.
//
// iOS gates network access in JS (WebSocket/fetch/XHR proxied or removed);
// storage, workers, DOM embedding, and WebRTC are gated too.
// ============================================================================

import { createIOSBridge } from './ios-bridge.js';
import {
  blockIframeCreation,
  deleteLegacyNetwork,
  disableCookies,
  disableSendBeacon,
  gateFetchSameOrigin,
  gateStorage,
  gateWebSocketToBridge,
  gateWorkers,
  installWebRtcGate,
} from './lockdown.js';

// Network — gated in JS on iOS.
gateWebSocketToBridge();
gateFetchSameOrigin();
deleteLegacyNetwork();
disableSendBeacon();

// Storage / DOM / workers — shared.
gateStorage();
disableCookies();
gateWorkers();
blockIframeCreation();

// WebRTC — permission-gated over the iOS WKScriptMessageHandler bridge.
installWebRtcGate(createIOSBridge());

export {};
