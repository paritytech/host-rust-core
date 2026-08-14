// =============================================================================
// Composable isolation steps.
//
// Each function applies one lockdown to the product realm. The per-platform
// entry points (index-ios.ts, index-android.ts) compose the subset their host
// needs — iOS gates network in JS, Android leaves network to a native
// interceptor, and both share storage/worker/DOM/WebRTC gating.
// =============================================================================

import { freezeAndDelete, freezeValue } from './freeze.js';
import type { NativeTransport } from './native-transport.js';
import { WebRtcManager, createWebRtcAccessRequester } from './webrtc-manager.js';

// --- WebSocket constructible only for the bridge URL ---
export function gateWebSocketToBridge(): void {
  const NativeWebSocket = window.WebSocket;
  const bridgeUrl: string | undefined = (
    window as unknown as { __truapi_localhost?: { url?: string } }
  ).__truapi_localhost?.url;

  const gated = new Proxy(NativeWebSocket, {
    construct(_target, args: [string, ...unknown[]]) {
      if (bridgeUrl !== undefined && args[0] === bridgeUrl) {
        return new NativeWebSocket(args[0]);
      }
      throw new TypeError('Network access is not allowed');
    },
  });

  freezeValue(window, 'WebSocket', gated);

  // Close the prototype-constructor bypass: `new window.WebSocket.prototype.constructor(url)`
  // would reach the ungated native constructor without this.
  try {
    Object.defineProperty(NativeWebSocket.prototype, 'constructor', {
      value: gated,
      writable: false,
      configurable: false,
    });
  } catch {
    /* best effort */
  }
}

// --- Network (iOS): fetch gated to same-origin only ---
export function gateFetchSameOrigin(): void {
  // Capture native fetch before installing the gate.
  const nativeFetch = window.fetch.bind(window);
  freezeValue(
    window,
    'fetch',
    (input: RequestInfo | URL, init?: RequestInit) => {
      try {
        const raw =
          typeof input === 'string'
            ? input
            : input instanceof URL
              ? input.href
              : input.url;
        const url = new URL(raw, window.location.href);
        if (url.origin === window.location.origin) {
          return nativeFetch(input, init);
        }
      } catch {
        /* fall through to rejection */
      }
      return Promise.reject(new TypeError('Network access is not allowed'));
    },
  );
}

// --- Network (iOS): delete APIs with no future permission path ---
export function deleteLegacyNetwork(): void {
  freezeAndDelete(window, 'XMLHttpRequest');
  freezeAndDelete(window, 'EventSource');
}

// --- Network (iOS): sendBeacon is a no-op ---
export function disableSendBeacon(): void {
  freezeValue(navigator, 'sendBeacon', () => false);
}

// --- Storage: no persistence ---
export function gateStorage(): void {
  freezeAndDelete(window, 'indexedDB');
  freezeAndDelete(window, 'caches');
}

// --- Cookies: document.cookie is an inert getter/setter ---
export function disableCookies(): void {
  try {
    Object.defineProperty(document, 'cookie', {
      get: () => '',
      set: () => {},
      configurable: false,
    });
  } catch {
    /* best effort */
  }
}

// --- Workers: no shared workers or service workers ---
export function gateWorkers(): void {
  freezeAndDelete(window, 'SharedWorker');

  if (navigator.serviceWorker) {
    try {
      Object.defineProperty(navigator, 'serviceWorker', {
        value: Object.freeze({
          register: () => {
            throw new Error('ServiceWorker is not available');
          },
        }),
        writable: false,
        configurable: false,
      });
    } catch {
      /* best effort */
    }
  }
}

// --- DOM: block iframe creation ---
export function blockIframeCreation(): void {
  const createElement = document.createElement.bind(document);
  freezeValue(
    document,
    'createElement',
    (tagName: string, options?: ElementCreationOptions) => {
      if (tagName.toLowerCase() === 'iframe') {
        throw new Error('iframe creation is not allowed');
      }
      return createElement(tagName, options);
    },
  );
}

// --- WebRTC: permission-gated when the native bridge is present, else blocked ---
export function installWebRtcGate(bridge: NativeTransport | undefined): void {
  const NativeRTC = window.RTCPeerConnection;
  if (NativeRTC && bridge) {
    freezeValue(
      window,
      'RTCPeerConnection',
      new WebRtcManager(NativeRTC, createWebRtcAccessRequester(bridge))
        .connectionClass,
    );
  } else {
    // Fail-closed: no bridge => WebRTC stays blocked.
    freezeAndDelete(window, 'RTCPeerConnection');
  }
}
