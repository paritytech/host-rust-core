// ============================================================================
// TrUAPI mode lockdown. Runs AFTER LocalhostBridgeBootstrap (native injects
// the bootstrap first), which publishes the bridge endpoint on
// window.__truapi_localhost and exposes __HOST_API_PORT__ / __HOST_WEBVIEW_MARK__.
// The bootstrap dials its WebSocket lazily (inside port.start()), so
// window.WebSocket must remain constructible for exactly the bridge URL.
// ============================================================================

// =============================================================================
// Isolation: Lock down globals so product scripts cannot access platform APIs.
// =============================================================================

function freezeAndDelete(obj: any, prop: string) {
  try {
    Object.defineProperty(obj, prop, {
      get: () => undefined,
      set() { /* silently ignore */ },
      configurable: false,
    });
  } catch {
    // Property may already be non-configurable; try delete as fallback
    try { delete obj[prop]; } catch { /* best effort */ }
  }
}

function freezeValue(obj: any, prop: string, value: any) {
  try {
    // Use a getter instead of a data property with writable:false.
    // A non-writable data property on the prototype chain prevents
    // descendant objects from shadowing it, which breaks polyfills
    // that create objects with window/self as prototype.
    Object.defineProperty(obj, prop, {
      get: () => value,
      set() { /* silently ignore */ },
      configurable: false,
    });
  } catch { /* best effort */ }
}

// Capture native fetch BEFORE lockdown so the same-origin gate can use it.
const _nativeFetch = window.fetch.bind(window);

const _NativeWebSocket = window.WebSocket;
const _bridgeUrl: string | undefined = (window as any).__truapi_localhost?.url;

const _GatedWebSocket = new Proxy(window.WebSocket, {
  construct(target, args: [string, ...unknown[]]) {
    if (_bridgeUrl !== undefined && args[0] === _bridgeUrl) {
      return new _NativeWebSocket(args[0]);
    }
    throw new TypeError('Network access is not allowed');
  },
});

freezeValue(window, 'WebSocket', _GatedWebSocket);

// Close the prototype-constructor bypass: `new window.WebSocket.prototype.constructor(url)`
// would reach the ungated native constructor without this.
try {
  Object.defineProperty(_NativeWebSocket.prototype, 'constructor', {
    value: _GatedWebSocket,
    writable: false,
    configurable: false,
  });
} catch { /* best effort */ }

// --- Network: fetch gated to same-origin only ---
freezeValue(window, 'fetch', (input: RequestInfo | URL, init?: RequestInit) => {
  try {
    const raw = typeof input === 'string' ? input
      : input instanceof URL ? input.href
      : input.url;
    const url = new URL(raw, window.location.href);
    if (url.origin === window.location.origin) {
      return _nativeFetch(input, init);
    }
  } catch { /* fall through to rejection */ }
  return Promise.reject(new TypeError('Network access is not allowed'));
});

// --- Network: delete (no future permission path) ---
freezeAndDelete(window, 'XMLHttpRequest');
freezeAndDelete(window, 'EventSource');

freezeValue(navigator, 'sendBeacon', () => false);

// --- Storage ---
freezeAndDelete(window, 'indexedDB');
freezeAndDelete(window, 'caches');

// document.cookie — redefine as no-op getter/setter
try {
  Object.defineProperty(document, 'cookie', {
    get: () => '',
    set: () => {},
    configurable: false,
  });
} catch { /* best effort */ }

// --- Workers ---
freezeAndDelete(window, 'SharedWorker');

if (navigator.serviceWorker) {
  try {
    Object.defineProperty(navigator, 'serviceWorker', {
      value: Object.freeze({
        register: () => { throw new Error('ServiceWorker is not available'); },
      }),
      writable: false,
      configurable: false,
    });
  } catch { /* best effort */ }
}

// --- DOM: block iframe creation ---
const _createElement = document.createElement.bind(document);
freezeValue(document, 'createElement', (tagName: string, options?: ElementCreationOptions) => {
  if (tagName.toLowerCase() === 'iframe') {
    throw new Error('iframe creation is not allowed');
  }
  return _createElement(tagName, options);
});

export {};
