"use strict";
(() => {
  // src/index.ts
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
  var _nativeFetch = window.fetch.bind(window);
  var _NativeWebSocket = window.WebSocket;
  var _bridgeUrl = window.__truapi_localhost?.url;
  var _GatedWebSocket = new Proxy(window.WebSocket, {
    construct(target, args) {
      if (_bridgeUrl !== void 0 && args[0] === _bridgeUrl) {
        return new _NativeWebSocket(args[0]);
      }
      throw new TypeError("Network access is not allowed");
    }
  });
  freezeValue(window, "WebSocket", _GatedWebSocket);
  try {
    Object.defineProperty(_NativeWebSocket.prototype, "constructor", {
      value: _GatedWebSocket,
      writable: false,
      configurable: false
    });
  } catch {
  }
  freezeValue(window, "fetch", (input, init) => {
    try {
      const raw = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
      const url = new URL(raw, window.location.href);
      if (url.origin === window.location.origin) {
        return _nativeFetch(input, init);
      }
    } catch {
    }
    return Promise.reject(new TypeError("Network access is not allowed"));
  });
  freezeAndDelete(window, "XMLHttpRequest");
  freezeAndDelete(window, "EventSource");
  freezeValue(navigator, "sendBeacon", () => false);
  freezeAndDelete(window, "indexedDB");
  freezeAndDelete(window, "caches");
  try {
    Object.defineProperty(document, "cookie", {
      get: () => "",
      set: () => {
      },
      configurable: false
    });
  } catch {
  }
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
  var _createElement = document.createElement.bind(document);
  freezeValue(document, "createElement", (tagName, options) => {
    if (tagName.toLowerCase() === "iframe") {
      throw new Error("iframe creation is not allowed");
    }
    return _createElement(tagName, options);
  });
  freezeAndDelete(window, "RTCPeerConnection");
})();
