"use strict";
(() => {
  // src/freeze.ts
  var failures = [];
  function describe(obj) {
    if (obj === globalThis) return "window";
    const name = obj?.constructor?.name;
    return typeof name === "string" && name.length > 0 ? name : "object";
  }
  function recordFailure(obj, prop) {
    failures.push(`${describe(obj)}.${prop}`);
  }
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
    if (obj?.[prop] !== void 0) {
      recordFailure(obj, prop);
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
    if (obj?.[prop] !== value) {
      recordFailure(obj, prop);
    }
  }
  function freezeCustom(obj, prop, descriptor, verify) {
    try {
      Object.defineProperty(obj, prop, { configurable: false, ...descriptor });
    } catch {
    }
    let locked = false;
    try {
      locked = verify(obj?.[prop]);
    } catch {
    }
    if (!locked) {
      recordFailure(obj, prop);
    }
  }
  function reportLockdownFailures() {
    if (failures.length === 0) {
      return;
    }
    const message = `TrUAPI container lockdown failed for: ${failures.join(", ")}`;
    try {
      console.error(message);
    } catch {
    }
    throw new Error(message);
  }

  // src/webrtc.ts
  var POLICY_GLOBAL = "__truapi_policy__";
  function installWebRtcPolicy(win, allowed) {
    if (allowed === true) {
      return;
    }
    freezeAndDelete(win, "RTCPeerConnection");
    freezeAndDelete(win, "webkitRTCPeerConnection");
    freezeAndDelete(win, "mozRTCPeerConnection");
  }
  function consumeWebRtcPolicy(win) {
    const allowed = win?.[POLICY_GLOBAL]?.webRtcAllowed;
    freezeAndDelete(win, POLICY_GLOBAL);
    return allowed;
  }

  // src/index.ts
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
  freezeCustom(
    _NativeWebSocket.prototype,
    "constructor",
    { value: _GatedWebSocket, writable: false },
    (current) => current === _GatedWebSocket
  );
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
  freezeCustom(
    document,
    "cookie",
    { get: () => "", set: () => {
    } },
    (current) => current === ""
  );
  freezeAndDelete(window, "SharedWorker");
  if (navigator.serviceWorker) {
    const _stubServiceWorker = Object.freeze({
      register: () => {
        throw new Error("ServiceWorker is not available");
      }
    });
    freezeCustom(
      navigator,
      "serviceWorker",
      { value: _stubServiceWorker, writable: false },
      (current) => current === _stubServiceWorker
    );
  }
  var _createElement = document.createElement.bind(document);
  freezeValue(document, "createElement", (tagName, options) => {
    if (tagName.toLowerCase() === "iframe") {
      throw new Error("iframe creation is not allowed");
    }
    return _createElement(tagName, options);
  });
  installWebRtcPolicy(window, consumeWebRtcPolicy(window));
  reportLockdownFailures();
})();
