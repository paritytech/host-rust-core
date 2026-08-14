"use strict";
(() => {
  // src/freeze.ts
  function freezeAndDelete(obj, prop) {
    try {
      Object.defineProperty(obj, prop, {
        get: () => void 0,
        set() {
        },
        configurable: false
      });
    } catch {
      try {
        delete obj[prop];
      } catch {
      }
    }
  }
  function freezeValue(obj, prop, value) {
    try {
      Object.defineProperty(obj, prop, {
        get: () => value,
        set() {
        },
        configurable: false
      });
    } catch {
    }
  }

  // src/native-transport.ts
  function randomId() {
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);
    let hex = "";
    for (const byte of bytes) {
      hex += byte.toString(16).padStart(2, "0");
    }
    return hex;
  }
  function createNativeTransport(sendToNative) {
    const pending = /* @__PURE__ */ new Map();
    function callNative(method, params) {
      const id = randomId();
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        sendToNative(JSON.stringify({ type: "request", id, method, params }));
      });
    }
    function dispatch(id, payload) {
      const entry = pending.get(id);
      if (entry === void 0) {
        return;
      }
      pending.delete(id);
      let reply;
      try {
        reply = typeof payload === "string" ? JSON.parse(payload) : payload;
      } catch {
        entry.reject(new Error("Malformed native reply"));
        return;
      }
      if (reply.error !== void 0 && reply.error !== null) {
        const error = reply.error;
        const code = typeof error === "string" ? error : error.code ?? "native_error";
        const message = typeof error === "string" ? error : error.message ?? code;
        entry.reject(Object.assign(new Error(message), { code }));
        return;
      }
      entry.resolve(reply.value);
    }
    return { callNative, dispatch };
  }

  // src/bridge-contract.ts
  var HANDLER_NAME = "__container__";
  var CALLBACK_NAME = "__container_callback__";
  function installNativeBridge(send) {
    const transport = createNativeTransport(send);
    freezeValue(window, CALLBACK_NAME, (id, payload) => {
      transport.dispatch(id, payload);
    });
    return transport;
  }

  // src/ios-bridge.ts
  function getMessageHandler() {
    const webkit = window.webkit;
    return webkit?.messageHandlers?.[HANDLER_NAME];
  }
  function createIOSBridge() {
    const handler = getMessageHandler();
    if (handler === void 0) {
      return void 0;
    }
    const postMessage = handler.postMessage.bind(handler);
    return installNativeBridge((message) => {
      postMessage(message);
    });
  }

  // src/webrtc-manager.ts
  function createWebRtcAccessRequester(transport) {
    return () => transport.callNative("allowWebRtcAccess", {}).then(
      (reply) => typeof reply === "object" && reply !== null && reply.allowed === true
    );
  }
  var GATED_METHODS = [
    "createOffer",
    "createAnswer",
    "setLocalDescription",
    "setRemoteDescription",
    "addIceCandidate"
  ];
  var WebRtcManager = class {
    constructor(nativeConnectionClass, requestAccess) {
      const decisions = /* @__PURE__ */ new WeakMap();
      const ensureAllowed = (connection) => {
        let decision = decisions.get(connection);
        if (decision === void 0) {
          decision = requestAccess();
          decisions.set(connection, decision);
        }
        return decision.then((allowed) => {
          if (!allowed) {
            connection.close();
            throw new TypeError("WebRTC access is not allowed");
          }
        });
      };
      const proto = nativeConnectionClass.prototype;
      for (const name of GATED_METHODS) {
        const nativeMethod = proto[name];
        Object.defineProperty(proto, name, {
          configurable: false,
          writable: false,
          enumerable: true,
          value: async function(...args) {
            await ensureAllowed(this);
            return nativeMethod.apply(this, args);
          }
        });
      }
      this.connectionClass = nativeConnectionClass;
    }
  };

  // src/lockdown.ts
  function gateWebSocketToBridge() {
    const NativeWebSocket = window.WebSocket;
    const bridgeUrl = window.__truapi_localhost?.url;
    const gated = new Proxy(NativeWebSocket, {
      construct(_target, args) {
        if (bridgeUrl !== void 0 && args[0] === bridgeUrl) {
          return new NativeWebSocket(args[0]);
        }
        throw new TypeError("Network access is not allowed");
      }
    });
    freezeValue(window, "WebSocket", gated);
    try {
      Object.defineProperty(NativeWebSocket.prototype, "constructor", {
        value: gated,
        writable: false,
        configurable: false
      });
    } catch {
    }
  }
  function gateFetchSameOrigin() {
    const nativeFetch = window.fetch.bind(window);
    freezeValue(
      window,
      "fetch",
      (input, init) => {
        try {
          const raw = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
          const url = new URL(raw, window.location.href);
          if (url.origin === window.location.origin) {
            return nativeFetch(input, init);
          }
        } catch {
        }
        return Promise.reject(new TypeError("Network access is not allowed"));
      }
    );
  }
  function deleteLegacyNetwork() {
    freezeAndDelete(window, "XMLHttpRequest");
    freezeAndDelete(window, "EventSource");
  }
  function disableSendBeacon() {
    freezeValue(navigator, "sendBeacon", () => false);
  }
  function gateStorage() {
    freezeAndDelete(window, "indexedDB");
    freezeAndDelete(window, "caches");
  }
  function disableCookies() {
    try {
      Object.defineProperty(document, "cookie", {
        get: () => "",
        set: () => {
        },
        configurable: false
      });
    } catch {
    }
  }
  function gateWorkers() {
    freezeAndDelete(window, "SharedWorker");
    if (navigator.serviceWorker) {
      try {
        Object.defineProperty(navigator, "serviceWorker", {
          value: Object.freeze({
            register: () => {
              throw new Error("ServiceWorker is not available");
            }
          }),
          writable: false,
          configurable: false
        });
      } catch {
      }
    }
  }
  function blockIframeCreation() {
    const createElement = document.createElement.bind(document);
    freezeValue(
      document,
      "createElement",
      (tagName, options) => {
        if (tagName.toLowerCase() === "iframe") {
          throw new Error("iframe creation is not allowed");
        }
        return createElement(tagName, options);
      }
    );
  }
  function installWebRtcGate(bridge) {
    const NativeRTC = window.RTCPeerConnection;
    if (NativeRTC && bridge) {
      freezeValue(
        window,
        "RTCPeerConnection",
        new WebRtcManager(NativeRTC, createWebRtcAccessRequester(bridge)).connectionClass
      );
    } else {
      freezeAndDelete(window, "RTCPeerConnection");
    }
  }

  // src/index-ios.ts
  gateWebSocketToBridge();
  gateFetchSameOrigin();
  deleteLegacyNetwork();
  disableSendBeacon();
  gateStorage();
  disableCookies();
  gateWorkers();
  blockIframeCreation();
  installWebRtcGate(createIOSBridge());
})();
