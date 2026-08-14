// ============================================================================
// Android lockdown entry point.
//
// Android leaves fetch to a native WebView request interceptor, so the container
// does NOT gate fetch here. Everything else is gated in JS as on iOS: WebSocket
// (constructible only for the bridge URL), XMLHttpRequest/EventSource removed,
// sendBeacon disabled, plus storage/worker/DOM/WebRTC gating.
// ============================================================================

import { createAndroidBridge } from './android-bridge.js';
import {
  blockIframeCreation,
  deleteLegacyNetwork,
  disableCookies,
  disableSendBeacon,
  gateStorage,
  gateWebSocketToBridge,
  gateWorkers,
  installWebRtcGate,
} from './lockdown.js';

// Network — gated in JS except fetch, which the native interceptor handles.
gateWebSocketToBridge();
deleteLegacyNetwork();
disableSendBeacon();

// Storage / DOM / workers — shared.
gateStorage();
disableCookies();
gateWorkers();
blockIframeCreation();

// WebRTC — permission-gated over the Android WebView JavascriptInterface bridge.
installWebRtcGate(createAndroidBridge());

export {};
