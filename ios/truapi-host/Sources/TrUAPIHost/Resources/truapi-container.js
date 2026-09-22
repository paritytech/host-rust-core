"use strict";
(() => {
  var __defProp = Object.defineProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };

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
  function installWebRtcPolicy(win, authorize) {
    const aliases = [
      "RTCPeerConnection",
      "webkitRTCPeerConnection",
      "mozRTCPeerConnection"
    ];
    if (typeof authorize !== "function") {
      for (const name of aliases) freezeAndDelete(win, name);
      return;
    }
    const apply = Reflect.apply;
    const construct = Reflect.construct;
    const get = Reflect.get;
    const define = Object.defineProperty;
    const NativePromise = win.Promise;
    const NativeError = win.TypeError;
    const NativeProxy = Proxy;
    const finite = Number.isFinite;
    const truncate = Math.trunc;
    const states = /* @__PURE__ */ new WeakMap();
    const weakGet = WeakMap.prototype.get;
    const weakSet = WeakMap.prototype.set;
    const installed = /* @__PURE__ */ new Map();
    function state(connection) {
      const value = apply(weakGet, states, [connection]);
      if (!value) throw new NativeError("Invalid RTCPeerConnection receiver");
      return value;
    }
    function configuration(input) {
      const result = { value: input, pool: 0 };
      if (input == null) return result;
      if (typeof input !== "object" && typeof input !== "function") {
        throw new NativeError("RTCConfiguration must be an object");
      }
      result.value = new NativeProxy(
        {},
        {
          get(_target, name) {
            const value = get(input, name, input);
            if (name !== "iceCandidatePoolSize") return value;
            const number = value === void 0 ? 0 : +value;
            const pool = truncate(number);
            if (!finite(number) || pool < 0 || pool > 255) {
              throw new NativeError(
                "iceCandidatePoolSize must be between 0 and 255"
              );
            }
            result.pool = pool;
            return 0;
          }
        }
      );
      return result;
    }
    function withPool(value, pool) {
      define(value, "iceCandidatePoolSize", {
        value: pool,
        writable: true,
        enumerable: true,
        configurable: true
      });
      return value;
    }
    function drain(connection, current) {
      let call = current.head;
      current.head = null;
      current.tail = null;
      while (call) {
        try {
          if (current.phase === "allowed") {
            call.resolve(apply(call.method, connection, call.args));
          } else {
            const error = new NativeError(
              current.phase === "closed" ? "WebRTC connection is closed" : "WebRTC access is not allowed"
            );
            if (call.errorCallback) {
              apply(call.errorCallback, void 0, [error]);
              call.resolve(void 0);
            } else {
              call.reject(error);
            }
          }
        } catch (error) {
          call.reject(error);
        }
        call = call.next;
      }
    }
    for (const alias of aliases) {
      let finish2 = function(connection, current, allowed) {
        if (current.phase !== "pending") return;
        current.phase = allowed === true ? "allowed" : "denied";
        current.cancel?.();
        current.cancel = null;
        try {
          if (current.phase === "allowed" && current.pool !== 0) {
            apply(nativeSetConfiguration, connection, [
              withPool(
                apply(nativeGetConfiguration, connection, []),
                current.pool
              )
            ]);
          } else if (current.phase === "denied") {
            apply(nativeClose, connection, []);
          }
        } catch {
          current.phase = "denied";
          try {
            apply(nativeClose, connection, []);
          } catch {
          }
        }
        drain(connection, current);
      };
      var finish = finish2;
      const Native = win[alias];
      if (typeof Native !== "function") continue;
      const previous = installed.get(Native) ?? installed.get(Native.prototype);
      if (previous) {
        freezeValue(win, alias, previous);
        continue;
      }
      const prototype = Native.prototype;
      const nativeClose = prototype.close;
      const nativeGetConfiguration = prototype.getConfiguration;
      const nativeSetConfiguration = prototype.setConfiguration;
      const Guarded = new NativeProxy(Native, {
        construct(_target, args, newTarget) {
          const requested = configuration(args[0]);
          define(args, "0", {
            value: requested.value,
            writable: true,
            enumerable: true,
            configurable: true
          });
          const connection = construct(Native, args, newTarget);
          apply(weakSet, states, [
            connection,
            {
              phase: "idle",
              pool: requested.pool,
              head: null,
              tail: null,
              cancel: null
            }
          ]);
          return connection;
        }
      });
      freezeValue(prototype, "constructor", Guarded);
      for (const method of [
        "createOffer",
        "createAnswer",
        "setLocalDescription",
        "setRemoteDescription",
        "addIceCandidate"
      ]) {
        const nativeMethod = prototype[method];
        freezeValue(prototype, method, function(...args) {
          return new NativePromise(
            (resolve, reject) => {
              const current = state(this);
              const callbackIndex = method === "createOffer" || method === "createAnswer" ? 0 : 1;
              const errorCallback = typeof args[callbackIndex] === "function" && typeof args[callbackIndex + 1] === "function" ? args[callbackIndex + 1] : void 0;
              const call = {
                method: nativeMethod,
                args,
                errorCallback,
                resolve,
                reject,
                next: null
              };
              if (current.tail) current.tail.next = call;
              else current.head = call;
              current.tail = call;
              if (current.phase !== "idle" && current.phase !== "pending") {
                drain(this, current);
                return;
              }
              if (current.phase === "pending") return;
              current.phase = "pending";
              try {
                const cancel = authorize(
                  (allowed) => finish2(this, current, allowed)
                );
                if (current.phase === "pending") current.cancel = cancel;
                else cancel();
              } catch {
                finish2(this, current, false);
              }
            }
          );
        });
      }
      freezeValue(
        prototype,
        "setConfiguration",
        function(input) {
          const current = state(this);
          if (current.phase === "allowed")
            return apply(nativeSetConfiguration, this, [input]);
          const requested = configuration(input);
          const result = apply(nativeSetConfiguration, this, [requested.value]);
          current.pool = requested.pool;
          return result;
        }
      );
      freezeValue(prototype, "getConfiguration", function() {
        const current = state(this);
        const value = apply(nativeGetConfiguration, this, []);
        return current.phase === "allowed" ? value : withPool(value, current.pool);
      });
      freezeValue(prototype, "close", function() {
        const current = state(this);
        current.phase = "closed";
        current.cancel?.();
        current.cancel = null;
        try {
          return apply(nativeClose, this, []);
        } finally {
          drain(this, current);
        }
      });
      installed.set(Native, Guarded);
      installed.set(prototype, Guarded);
      freezeValue(win, alias, Guarded);
    }
  }

  // src/network.ts
  function getter(prototype, name) {
    return Object.getOwnPropertyDescriptor(prototype, name).get;
  }
  function installFetchGate(win, authorize) {
    const nativeFetch = win.fetch.bind(win);
    const NativeRequest = win.Request;
    const NativeURL = win.URL;
    const NativePromise = win.Promise;
    const NetworkError = win.TypeError;
    const apply = Reflect.apply;
    const requestUrl = getter(NativeRequest.prototype, "url");
    const requestSignal = getter(NativeRequest.prototype, "signal");
    const urlOrigin = getter(NativeURL.prototype, "origin");
    const urlProtocol = getter(NativeURL.prototype, "protocol");
    const urlHost = getter(NativeURL.prototype, "host");
    const signalAborted = getter(win.AbortSignal.prototype, "aborted");
    const signalReason = getter(win.AbortSignal.prototype, "reason");
    const addEventListener = win.EventTarget.prototype.addEventListener;
    const removeEventListener = win.EventTarget.prototype.removeEventListener;
    function origin(url) {
      const value = apply(urlOrigin, url, []);
      return value === "null" ? `${apply(urlProtocol, url, [])}//${apply(urlHost, url, [])}` : value;
    }
    const productOrigin = win.location && origin(new NativeURL(win.location.href));
    freezeValue(
      win,
      "fetch",
      (input, init) => new NativePromise((resolve, reject) => {
        let signal;
        let settled = false;
        let cancelAuthorization;
        function finish() {
          settled = true;
          cancelAuthorization?.();
          if (signal) apply(removeEventListener, signal, ["abort", abort]);
        }
        function deny() {
          finish();
          reject(new NetworkError("Network access is not allowed"));
        }
        function abort() {
          if (settled) return;
          finish();
          reject(apply(signalReason, signal, []));
        }
        try {
          let authorized2 = function(allowed) {
            if (settled) return;
            if (allowed !== true) {
              deny();
              return;
            }
            finish();
            try {
              resolve(nativeFetch(request));
            } catch (error) {
              reject(error);
            }
          };
          var authorized = authorized2;
          const request = new NativeRequest(input, init);
          const destination = apply(requestUrl, request, []);
          const url = new NativeURL(destination);
          const sameOrigin = origin(url) === productOrigin;
          const protocol = apply(urlProtocol, url, []);
          if (!sameOrigin && protocol !== "http:" && protocol !== "https:") {
            deny();
            return;
          }
          signal = apply(requestSignal, request, []);
          if (apply(signalAborted, signal, [])) {
            abort();
            return;
          }
          apply(addEventListener, signal, ["abort", abort]);
          if (sameOrigin) authorized2(true);
          else cancelAuthorization = authorize(destination, authorized2);
        } catch (error) {
          if (signal) deny();
          else reject(error);
        }
      })
    );
  }

  // src/xhr.ts
  function installXhrGate(win, authorize) {
    const NativeXhr = win.XMLHttpRequest;
    if (!NativeXhr) return;
    const prototype = NativeXhr.prototype;
    const apply = Reflect.apply;
    const descriptor = Object.getOwnPropertyDescriptor;
    const nativeOpen = prototype.open;
    const nativeSend = prototype.send;
    const nativeAbort = prototype.abort;
    const nativeHeader = prototype.setRequestHeader;
    const nativeMime = prototype.overrideMimeType;
    const ready = descriptor(prototype, "readyState").get;
    const upload = descriptor(prototype, "upload").get;
    const timeout = descriptor(prototype, "timeout");
    const credentials = descriptor(prototype, "withCredentials");
    const responseType = descriptor(prototype, "responseType");
    const dispatch = win.EventTarget.prototype.dispatchEvent;
    const NativeEvent = win.Event;
    const NativeProgress = win.ProgressEvent;
    const NativeError = win.DOMException;
    const NativeTypeError = win.TypeError;
    const NativeURL = win.URL;
    const href = descriptor(NativeURL.prototype, "href").get;
    const origin = descriptor(NativeURL.prototype, "origin").get;
    const protocol = descriptor(NativeURL.prototype, "protocol").get;
    const host = descriptor(NativeURL.prototype, "host").get;
    const baseURI = win.Node && descriptor(win.Node.prototype, "baseURI")?.get;
    const uppercase = String.prototype.toUpperCase;
    const codeUnit = String.prototype.charCodeAt;
    const stringify = String;
    const states = /* @__PURE__ */ new WeakMap();
    const weakGet = WeakMap.prototype.get;
    const weakSet = WeakMap.prototype.set;
    const now = win.performance.now.bind(win.performance);
    const schedule = win.setTimeout.bind(win);
    const unschedule = win.clearTimeout.bind(win);
    const maximum = Math.max;
    const NativeBytes = win.Uint8Array;
    const bufferLength = descriptor(
      win.ArrayBuffer.prototype,
      "byteLength"
    ).get;
    const viewPrototype = Object.getPrototypeOf(NativeBytes.prototype);
    const viewBuffer = descriptor(viewPrototype, "buffer").get;
    const viewOffset = descriptor(viewPrototype, "byteOffset").get;
    const viewLength = descriptor(viewPrototype, "byteLength").get;
    const dataBuffer = descriptor(win.DataView.prototype, "buffer").get;
    const dataOffset = descriptor(win.DataView.prototype, "byteOffset").get;
    const dataLength = descriptor(win.DataView.prototype, "byteLength").get;
    const isView = win.ArrayBuffer.isView;
    const blobSize = descriptor(win.Blob.prototype, "size").get;
    const NativeForm = win.FormData;
    const formEach = NativeForm.prototype.forEach;
    const formAppend = NativeForm.prototype.append;
    const NativeParams = win.URLSearchParams;
    const paramsString = NativeParams.prototype.toString;
    const nodeType = win.Node && descriptor(win.Node.prototype, "nodeType")?.get;
    const cloneNode = win.Node?.prototype.cloneNode;
    function lockAccessor(name, get, set) {
      const marker = {};
      let verifying = true;
      freezeCustom(
        prototype,
        name,
        {
          get() {
            if (verifying && this === prototype) return marker;
            return apply(get, this, []);
          },
          set
        },
        (value) => value === marker
      );
      verifying = false;
    }
    function request(xhr) {
      apply(ready, xhr, []);
      return apply(weakGet, states, [xhr]);
    }
    function current(xhr, state) {
      return apply(weakGet, states, [xhr]) === state;
    }
    function invalid() {
      throw new NativeError(
        "The request is not open or has already been sent",
        "InvalidStateError"
      );
    }
    function byteString(value) {
      if (typeof value === "symbol")
        throw new NativeTypeError("Cannot convert a Symbol to a string");
      const text = stringify(value);
      for (let index = 0; index < text.length; index++) {
        if (apply(codeUnit, text, [index]) > 255)
          throw new NativeTypeError(
            "ByteString contains a character outside the byte range"
          );
      }
      return text;
    }
    function sendable(xhr, state) {
      if (!state || !current(xhr, state) || state.pending || state.nativeStarted || state.overrideState !== void 0 || apply(ready, xhr, []) !== 1)
        invalid();
    }
    function urlOrigin(url) {
      const value = apply(origin, url, []);
      return value === "null" ? `${apply(protocol, url, [])}//${apply(host, url, [])}` : value;
    }
    const productOrigin = urlOrigin(new NativeURL(win.location.href));
    function cancel(state) {
      state.pending = false;
      state.cancel?.();
      state.cancel = void 0;
      if (state.deadline !== void 0) unschedule(state.deadline);
      state.deadline = void 0;
    }
    function fail(xhr, state, type) {
      if (!current(xhr, state) || !state.pending) return;
      cancel(state);
      apply(nativeAbort, xhr, []);
      state.overrideState = 4;
      apply(dispatch, xhr, [new NativeEvent("readystatechange")]);
      if (!current(xhr, state)) return;
      if (state.body) {
        const target = apply(upload, xhr, []);
        apply(dispatch, target, [new NativeProgress(type)]);
        if (!current(xhr, state)) return;
        apply(dispatch, target, [new NativeProgress("loadend")]);
        if (!current(xhr, state)) return;
      }
      apply(dispatch, xhr, [new NativeProgress(type)]);
      if (current(xhr, state))
        apply(dispatch, xhr, [new NativeProgress("loadend")]);
    }
    function deadline(xhr, state) {
      if (state.deadline !== void 0) unschedule(state.deadline);
      state.deadline = void 0;
      if (state.timeout !== 0) {
        state.deadline = schedule(
          () => fail(xhr, state, "timeout"),
          maximum(0, state.timeout - (now() - state.startedAt))
        );
      }
    }
    function copyBytes(buffer, offset, length) {
      apply(bufferLength, buffer, []);
      const source = new NativeBytes(buffer, offset, length);
      const copy = new NativeBytes(length);
      for (let index = 0; index < length; index++) copy[index] = source[index];
      return copy;
    }
    function snapshot(body) {
      if (body === void 0 || body === null) return null;
      if (isView(body)) {
        try {
          return copyBytes(
            apply(viewBuffer, body, []),
            apply(viewOffset, body, []),
            apply(viewLength, body, [])
          );
        } catch {
          return copyBytes(
            apply(dataBuffer, body, []),
            apply(dataOffset, body, []),
            apply(dataLength, body, [])
          );
        }
      }
      let length;
      try {
        length = apply(bufferLength, body, []);
      } catch {
      }
      if (length !== void 0) return copyBytes(body, 0, length);
      try {
        apply(blobSize, body, []);
        return body;
      } catch {
      }
      if (nodeType && cloneNode) {
        let document2 = false;
        try {
          document2 = apply(nodeType, body, []) === 9;
        } catch {
        }
        if (document2) return apply(cloneNode, body, [true]);
      }
      try {
        const copy = new NativeForm();
        apply(formEach, body, [
          (value, name) => {
            apply(formAppend, copy, [name, value]);
          }
        ]);
        return copy;
      } catch {
      }
      try {
        return new NativeParams(apply(paramsString, body, []));
      } catch {
      }
      if (typeof body === "symbol")
        throw new NativeTypeError("Cannot convert a Symbol to a string");
      return stringify(body);
    }
    freezeValue(
      prototype,
      "open",
      function(method, url, ...rest) {
        request(this);
        method = byteString(method);
        if (typeof url === "symbol")
          throw new NativeTypeError("Cannot convert a Symbol to a string");
        const inputUrl = stringify(url);
        function credential(index) {
          const value = rest.length > index ? rest[index] : null;
          if (value === null || value === void 0) return null;
          if (typeof value === "symbol")
            throw new NativeTypeError("Cannot convert a Symbol to a string");
          return stringify(value);
        }
        const username = credential(1);
        const password = credential(2);
        let destination;
        try {
          destination = new NativeURL(
            inputUrl,
            baseURI ? apply(baseURI, win.document, []) : win.document.baseURI
          );
        } catch {
          throw new NativeError("Invalid XMLHttpRequest URL", "SyntaxError");
        }
        if (rest.length && !rest[0]) {
          throw new NativeError(
            "synchronous XMLHttpRequest is not supported",
            "InvalidAccessError"
          );
        }
        const previous = request(this);
        const oldTimeout = apply(timeout.get, this, []);
        const oldState = apply(ready, this, []);
        const state = {
          url: apply(href, destination, []),
          method: apply(uppercase, method, []),
          sameOrigin: urlOrigin(destination) === productOrigin,
          supported: apply(protocol, destination, []) === "http:" || apply(protocol, destination, []) === "https:",
          pending: false,
          nativeStarted: false,
          body: false,
          overrideState: void 0,
          startedAt: 0,
          waited: 0,
          timeout: previous?.timeout ?? oldTimeout,
          deadline: void 0,
          cancel: void 0
        };
        apply(weakSet, states, [this, state]);
        try {
          apply(timeout.set, this, [state.timeout]);
          apply(nativeOpen, this, [method, state.url, true, username, password]);
        } catch (error) {
          apply(weakSet, states, [this, previous]);
          apply(timeout.set, this, [oldTimeout]);
          throw error;
        }
        if (previous) cancel(previous);
        if (current(this, state) && oldState === 1 && previous?.overrideState !== void 0)
          apply(dispatch, this, [new NativeEvent("readystatechange")]);
      }
    );
    freezeValue(prototype, "send", function(body) {
      const state = request(this);
      sendable(this, state);
      const payload = state.method === "GET" || state.method === "HEAD" ? null : snapshot(body);
      sendable(this, state);
      state.pending = true;
      state.body = payload !== null;
      state.startedAt = now();
      deadline(this, state);
      let sending = true;
      const failSend = (type) => {
        if (sending) schedule(() => fail(this, state, type), 0);
        else fail(this, state, type);
      };
      const decided = (allowed) => {
        if (!current(this, state) || !state.pending) return;
        if (allowed !== true) return failSend("error");
        state.waited = now() - state.startedAt;
        if (state.timeout && state.waited >= state.timeout)
          return failSend("timeout");
        cancel(state);
        state.nativeStarted = true;
        apply(timeout.set, this, [
          state.timeout ? maximum(1, state.timeout - state.waited) : 0
        ]);
        try {
          apply(nativeSend, this, [payload]);
        } catch {
          state.pending = true;
          state.nativeStarted = false;
          failSend("error");
        }
      };
      if (state.sameOrigin) decided(true);
      else if (!state.supported) decided(false);
      else {
        try {
          const cancellation = authorize(state.url, decided);
          if (!state.pending) cancellation();
          else state.cancel = cancellation;
        } catch {
          failSend("error");
        }
      }
      sending = false;
    });
    freezeValue(prototype, "abort", function() {
      const state = request(this);
      if (state?.pending) {
        fail(this, state, "abort");
        if (current(this, state) && state.overrideState === 4)
          state.overrideState = 0;
      } else {
        if (state?.overrideState !== void 0) state.overrideState = 0;
        apply(nativeAbort, this, []);
      }
    });
    freezeValue(
      prototype,
      "setRequestHeader",
      function(...args) {
        if (args.length < 2)
          throw new NativeTypeError("setRequestHeader requires two arguments");
        const name = byteString(args[0]);
        const value = byteString(args[1]);
        const state = request(this);
        if (state?.pending || state?.overrideState !== void 0) invalid();
        return apply(nativeHeader, this, [name, value]);
      }
    );
    freezeValue(
      prototype,
      "overrideMimeType",
      function(...args) {
        if (request(this)?.overrideState === 4) invalid();
        return apply(nativeMime, this, args);
      }
    );
    lockAccessor("readyState", function() {
      const state = request(this);
      return state?.overrideState ?? apply(ready, this, []);
    });
    lockAccessor(
      "timeout",
      function() {
        return request(this)?.timeout ?? apply(timeout.get, this, []);
      },
      function(value) {
        apply(timeout.set, this, [value]);
        const state = request(this);
        if (!state) return;
        state.timeout = apply(timeout.get, this, []);
        if (state.pending) deadline(this, state);
        else if (state.nativeStarted && apply(ready, this, []) !== 4)
          apply(timeout.set, this, [
            state.timeout ? maximum(1, state.timeout - state.waited) : 0
          ]);
      }
    );
    lockAccessor(
      "withCredentials",
      credentials.get,
      function(value) {
        const state = request(this);
        if (state?.pending || state?.overrideState === 4) invalid();
        apply(credentials.set, this, [value]);
      }
    );
    lockAccessor(
      "responseType",
      responseType.get,
      function(value) {
        if (request(this)?.overrideState === 4) invalid();
        apply(responseType.set, this, [value]);
      }
    );
    freezeValue(prototype, "constructor", NativeXhr);
    freezeValue(win, "XMLHttpRequest", NativeXhr);
  }

  // src/websocket.ts
  function installWebSocketGate(win, authorize, bridgeUrl, factory) {
    const NativeSocket = win.WebSocket;
    if (!NativeSocket) return;
    const apply = Reflect.apply;
    const descriptor = Object.getOwnPropertyDescriptor;
    const define = Object.defineProperty;
    const getPrototype = Object.getPrototypeOf;
    const freeze = Object.freeze;
    const create = Object.create;
    const owns = Object.prototype.hasOwnProperty;
    const nativePrototype = NativeSocket.prototype;
    const nativeSend = nativePrototype.send;
    const nativeClose = nativePrototype.close;
    const nativeProperties = create(null);
    const propertyNames = [
      "readyState",
      "bufferedAmount",
      "extensions",
      "protocol",
      "binaryType"
    ];
    for (const name of propertyNames)
      nativeProperties[name] = descriptor(nativePrototype, name);
    const NativeTarget = win.EventTarget;
    const add = NativeTarget.prototype.addEventListener;
    const remove = NativeTarget.prototype.removeEventListener;
    const dispatch = NativeTarget.prototype.dispatchEvent;
    const NativeEvent = win.Event;
    const NativeMessage = win.MessageEvent;
    const NativeClose = win.CloseEvent;
    const messageData = descriptor(NativeMessage.prototype, "data").get;
    const messageOrigin = descriptor(NativeMessage.prototype, "origin").get;
    const messageId = descriptor(NativeMessage.prototype, "lastEventId").get;
    const closeCode = descriptor(NativeClose.prototype, "code").get;
    const closeReason = descriptor(NativeClose.prototype, "reason").get;
    const closeClean = descriptor(NativeClose.prototype, "wasClean").get;
    const NativeError = win.DOMException;
    const NativeTypeError = win.TypeError;
    const NativeURL = win.URL;
    const href = descriptor(NativeURL.prototype, "href").get;
    const scheme = descriptor(NativeURL.prototype, "protocol");
    const baseURI = win.Node && descriptor(win.Node.prototype, "baseURI")?.get;
    const stringify = String;
    const indexOf = String.prototype.indexOf;
    const test = RegExp.prototype.test;
    const protocolToken = /^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/;
    const iterator = Symbol.iterator;
    const states = /* @__PURE__ */ new WeakMap();
    const weakGet = WeakMap.prototype.get;
    const weakSet = WeakMap.prototype.set;
    const schedule = win.setTimeout.bind(win);
    const encoder = new win.TextEncoder();
    const encode = win.TextEncoder.prototype.encode;
    const bufferLength = descriptor(
      win.ArrayBuffer.prototype,
      "byteLength"
    ).get;
    const viewPrototype = getPrototype(win.Uint8Array.prototype);
    const viewLength = descriptor(viewPrototype, "byteLength").get;
    const dataLength = descriptor(win.DataView.prototype, "byteLength").get;
    const blobSize = descriptor(win.Blob.prototype, "size").get;
    const isView = win.ArrayBuffer.isView;
    const floor = Math.floor;
    const min = Math.min;
    const max = Math.max;
    function state(socket) {
      const value = apply(weakGet, states, [socket]);
      if (!value) throw new NativeTypeError("Illegal WebSocket receiver");
      return value;
    }
    function text(value) {
      if (typeof value === "symbol")
        throw new NativeTypeError("Cannot convert a Symbol to a string");
      return stringify(value);
    }
    function protocols(value) {
      const result = [];
      if (value !== void 0) {
        const method = value !== null && (typeof value === "object" || typeof value === "function") ? value[iterator] : void 0;
        if (method !== void 0 && method !== null) {
          const sequence = apply(method, value, []);
          if (sequence === null || typeof sequence !== "object" && typeof sequence !== "function")
            throw new NativeTypeError("Invalid WebSocket protocol iterator");
          const next = sequence.next;
          while (true) {
            const item = apply(next, sequence, []);
            if (item === null || typeof item !== "object" && typeof item !== "function")
              throw new NativeTypeError(
                "Invalid WebSocket protocol iterator result"
              );
            if (item.done) break;
            result[result.length] = text(item.value);
          }
        } else result[0] = text(value);
      }
      for (let index = 0; index < result.length; index++) {
        const protocol = result[index];
        if (!apply(test, protocolToken, [protocol]))
          throw new NativeError("Invalid WebSocket protocol", "SyntaxError");
        for (let previous = 0; previous < index; previous++) {
          if (result[previous] === protocol)
            throw new NativeError("Duplicate WebSocket protocol", "SyntaxError");
        }
      }
      const iteration = create(null);
      iteration.value = function() {
        let index = 0;
        return {
          next() {
            return index < result.length ? { value: result[index++], done: false } : { value: void 0, done: true };
          }
        };
      };
      define(result, iterator, iteration);
      freeze(result);
      return result;
    }
    function cancel(current) {
      current.pending = false;
      current.cancel?.();
      current.cancel = void 0;
    }
    function fail(socket, current) {
      cancel(current);
      current.phase = 2;
      schedule(() => {
        current.phase = 3;
        apply(dispatch, socket, [new NativeEvent("error")]);
        apply(dispatch, socket, [
          new NativeClose("close", {
            code: 1006,
            reason: "",
            wasClean: false
          })
        ]);
      }, 0);
    }
    function connect(socket, current, requested) {
      const backend = factory ? factory(current.url, requested) : new NativeSocket(current.url, requested);
      const properties = create(null);
      for (let index = 0; index < propertyNames.length; index++) {
        const name = propertyNames[index];
        if (!factory) properties[name] = nativeProperties[name];
        else {
          let object = backend;
          while (object && !properties[name]) {
            properties[name] = descriptor(object, name);
            object = getPrototype(object);
          }
        }
      }
      const send = factory ? backend.send : nativeSend;
      const close = factory ? backend.close : nativeClose;
      current.backend = {
        read(name) {
          const property = properties[name];
          const get = property && apply(owns, property, ["get"]) ? property.get : void 0;
          return get ? apply(get, backend, []) : backend[name];
        },
        binaryType(value) {
          const property = properties.binaryType;
          const set = property && apply(owns, property, ["set"]) ? property.set : void 0;
          if (set) apply(set, backend, [value]);
          else backend.binaryType = value;
        },
        send(data) {
          apply(send, backend, [data]);
        },
        close(code, reason) {
          apply(close, backend, code === void 0 ? [] : [code, reason]);
        }
      };
      current.backend.binaryType(current.binaryType);
      apply(add, backend, [
        "open",
        () => {
          apply(dispatch, socket, [new NativeEvent("open")]);
        }
      ]);
      apply(add, backend, [
        "message",
        (event) => {
          apply(dispatch, socket, [
            new NativeMessage("message", {
              data: apply(messageData, event, []),
              origin: apply(messageOrigin, event, []),
              lastEventId: apply(messageId, event, []),
              source: null,
              ports: []
            })
          ]);
        }
      ]);
      apply(add, backend, [
        "error",
        () => {
          apply(dispatch, socket, [new NativeEvent("error")]);
        }
      ]);
      apply(add, backend, [
        "close",
        (event) => {
          apply(dispatch, socket, [
            new NativeClose("close", {
              code: apply(closeCode, event, []),
              reason: apply(closeReason, event, []),
              wasClean: apply(closeClean, event, [])
            })
          ]);
        }
      ]);
    }
    function validateClose(code, reason) {
      let converted;
      if (code !== void 0) {
        const value = +code;
        const clamped = value !== value ? 0 : min(65535, max(0, value));
        const lower = floor(clamped);
        converted = clamped - lower === 0.5 ? lower % 2 === 0 ? lower : lower + 1 : floor(clamped + 0.5);
        if (converted !== 1e3 && (converted < 3e3 || converted > 4999))
          throw new NativeError(
            "Invalid WebSocket close code",
            "InvalidAccessError"
          );
      }
      const description = reason === void 0 ? "" : text(reason);
      if (apply(encode, encoder, [description]).length > 123)
        throw new NativeError(
          "WebSocket close reason is too long",
          "SyntaxError"
        );
      return [converted, description];
    }
    function payload(data) {
      if (isView(data)) return data;
      try {
        apply(bufferLength, data, []);
        return data;
      } catch {
      }
      try {
        apply(blobSize, data, []);
        return data;
      } catch {
      }
      return text(data);
    }
    function dataSize(data) {
      if (isView(data)) {
        try {
          return apply(viewLength, data, []);
        } catch {
          return apply(dataLength, data, []);
        }
      }
      try {
        return apply(bufferLength, data, []);
      } catch {
      }
      try {
        return apply(blobSize, data, []);
      } catch {
      }
      return apply(encode, encoder, [text(data)]).length;
    }
    class GatedWebSocket extends NativeTarget {
      constructor(input, offered) {
        super();
        if (!arguments.length)
          throw new NativeTypeError("WebSocket requires a URL");
        const originalUrl = text(input);
        const requested = protocols(offered);
        let url;
        try {
          url = new NativeURL(
            originalUrl,
            baseURI ? apply(baseURI, win.document, []) : win.document?.baseURI
          );
        } catch {
          throw new NativeError("Invalid WebSocket URL", "SyntaxError");
        }
        const protocol = apply(scheme.get, url, []);
        if (protocol === "http:") apply(scheme.set, url, ["ws:"]);
        else if (protocol === "https:") apply(scheme.set, url, ["wss:"]);
        else if (protocol !== "ws:" && protocol !== "wss:")
          throw new NativeError("Invalid WebSocket URL scheme", "SyntaxError");
        const address = apply(href, url, []);
        if (apply(indexOf, address, ["#"]) !== -1)
          throw new NativeError(
            "WebSocket URLs cannot contain fragments",
            "SyntaxError"
          );
        if (bridgeUrl !== void 0 && originalUrl === bridgeUrl)
          return new NativeSocket(address, requested);
        const current = {
          url: address,
          phase: 0,
          binaryType: "blob",
          bufferedAmount: 0,
          pending: true,
          backend: void 0,
          cancel: void 0,
          handlers: create(null)
        };
        apply(weakSet, states, [this, current]);
        let constructing = true;
        const decided = (allowed) => {
          if (constructing) {
            schedule(() => decided(allowed), 0);
            return;
          }
          if (!current.pending) return;
          cancel(current);
          if (allowed !== true) return fail(this, current);
          try {
            connect(this, current, requested);
          } catch {
            fail(this, current);
          }
        };
        try {
          const cancellation = authorize(address, decided);
          if (!current.pending) cancellation();
          else current.cancel = cancellation;
        } catch {
          fail(this, current);
        }
        constructing = false;
      }
      get url() {
        return state(this).url;
      }
      get readyState() {
        const current = state(this);
        return current.backend?.read("readyState") ?? current.phase;
      }
      get bufferedAmount() {
        const current = state(this);
        return current.backend?.read("bufferedAmount") ?? current.bufferedAmount;
      }
      get protocol() {
        return state(this).backend?.read("protocol") ?? "";
      }
      get extensions() {
        return state(this).backend?.read("extensions") ?? "";
      }
      get binaryType() {
        return state(this).binaryType;
      }
      set binaryType(value) {
        const current = state(this);
        const converted = text(value);
        if (converted !== "blob" && converted !== "arraybuffer") return;
        current.binaryType = converted;
        current.backend?.binaryType(converted);
      }
      send(data) {
        const current = state(this);
        if (!arguments.length)
          throw new NativeTypeError("WebSocket.send requires data");
        const converted = payload(data);
        if ((current.backend?.read("readyState") ?? current.phase) === 0)
          throw new NativeError("WebSocket is not open", "InvalidStateError");
        if (current.backend) current.backend.send(converted);
        else current.bufferedAmount += dataSize(converted);
      }
      close(code, reason) {
        const current = state(this);
        const converted = validateClose(code, reason);
        if (current.backend) current.backend.close(converted[0], converted[1]);
        else if (current.phase === 0) fail(this, current);
      }
    }
    for (const name of ["open", "message", "error", "close"]) {
      define(GatedWebSocket.prototype, `on${name}`, {
        configurable: false,
        enumerable: true,
        get() {
          return state(this).handlers[name]?.callback ?? null;
        },
        set(value) {
          const current = state(this);
          const previous = current.handlers[name];
          if (typeof value !== "function") {
            if (previous) apply(remove, this, [name, previous.listener]);
            delete current.handlers[name];
          } else if (previous) previous.callback = value;
          else {
            const handler = {
              callback: value,
              listener: (event) => {
                apply(handler.callback, this, [event]);
              }
            };
            current.handlers[name] = handler;
            apply(add, this, [name, handler.listener]);
          }
        }
      });
    }
    for (const name of [
      "url",
      "readyState",
      "bufferedAmount",
      "protocol",
      "extensions",
      "binaryType"
    ])
      define(GatedWebSocket.prototype, name, {
        ...descriptor(GatedWebSocket.prototype, name),
        configurable: false
      });
    freezeValue(GatedWebSocket.prototype, "send", GatedWebSocket.prototype.send);
    freezeValue(
      GatedWebSocket.prototype,
      "close",
      GatedWebSocket.prototype.close
    );
    const constants = ["CONNECTING", "OPEN", "CLOSING", "CLOSED"];
    for (let index = 0; index < constants.length; index++) {
      freezeValue(GatedWebSocket, constants[index], index);
      freezeValue(GatedWebSocket.prototype, constants[index], index);
    }
    freezeValue(nativePrototype, "constructor", GatedWebSocket);
    freezeValue(GatedWebSocket.prototype, "constructor", GatedWebSocket);
    freezeValue(win, "WebSocket", GatedWebSocket);
  }

  // src/media.ts
  function installMediaPolicy(win, authorize) {
    const navigator2 = win.navigator;
    if (!navigator2) return;
    const devices = navigator2.mediaDevices;
    const nativeGetUserMedia = devices?.getUserMedia;
    const apply = Reflect.apply;
    const get = Reflect.get;
    const object = Object;
    const create = Object.create;
    const freeze = Object.freeze;
    const descriptor = Object.getOwnPropertyDescriptor;
    const prototypeOf = Object.getPrototypeOf;
    const NativePromise = win.Promise;
    const NativeTypeError = win.TypeError;
    const NativeDOMException = win.DOMException;
    function trackConstraints(value) {
      if (value === void 0) return false;
      if (value === null) return create(null);
      return object(value) === value ? value : !!value;
    }
    function snapshot(input) {
      if (input !== null && input !== void 0 && object(input) !== input) {
        throw new NativeTypeError("MediaStreamConstraints must be an object");
      }
      const missing = input === null || input === void 0;
      const audio = trackConstraints(
        missing ? void 0 : get(input, "audio", input)
      );
      const video = trackConstraints(
        missing ? void 0 : get(input, "video", input)
      );
      if (audio === false && video === false) {
        throw new NativeTypeError(
          "At least one of audio or video must be requested"
        );
      }
      const constraints = create(null);
      constraints.audio = audio;
      constraints.video = video;
      return freeze(constraints);
    }
    function capture(input, invoke, reject) {
      let settled = false;
      let cancel;
      try {
        let decided2 = function(allowed) {
          if (settled) return;
          settled = true;
          cancel?.();
          if (allowed !== true) {
            reject(
              new NativeDOMException(
                "Media capture is not allowed",
                "NotAllowedError"
              )
            );
            return;
          }
          try {
            invoke(constraints);
          } catch (error) {
            reject(error);
          }
        };
        var decided = decided2;
        const constraints = snapshot(input);
        if (typeof authorize !== "function") {
          decided2(false);
          return;
        }
        const cancellation = authorize(
          constraints.audio !== false,
          constraints.video !== false,
          decided2
        );
        if (settled) cancellation();
        else cancel = cancellation;
      } catch (error) {
        settled = true;
        cancel?.();
        reject(error);
      }
    }
    function lockMethod(target, name, method) {
      let owner = target;
      while (owner) {
        if (owner === target || descriptor(owner, name))
          freezeValue(owner, name, method);
        owner = prototypeOf(owner);
      }
    }
    if (typeof devices?.getDisplayMedia === "function") {
      lockMethod(devices, "getDisplayMedia", function() {
        return new NativePromise(
          (_resolve, reject) => {
            reject(
              new NativeDOMException(
                "Screen capture is not allowed",
                "NotAllowedError"
              )
            );
          }
        );
      });
    }
    if (typeof nativeGetUserMedia === "function") {
      lockMethod(devices, "getUserMedia", function(input) {
        return new NativePromise(
          (resolve, reject) => {
            if (this !== devices) {
              reject(new NativeTypeError("Invalid MediaDevices receiver"));
              return;
            }
            capture(
              input,
              (constraints) => resolve(apply(nativeGetUserMedia, devices, [constraints])),
              reject
            );
          }
        );
      });
    }
    for (const name of [
      "getUserMedia",
      "webkitGetUserMedia",
      "mozGetUserMedia",
      "msGetUserMedia"
    ]) {
      const native = navigator2[name];
      if (typeof native !== "function") continue;
      lockMethod(
        navigator2,
        name,
        function(input, success, failure) {
          if (this !== navigator2 || typeof success !== "function" || typeof failure !== "function") {
            throw new NativeTypeError(
              "Invalid getUserMedia receiver or callbacks"
            );
          }
          capture(
            input,
            (constraints) => {
              apply(native, navigator2, [constraints, success, failure]);
            },
            (error) => {
              apply(failure, void 0, [error]);
            }
          );
        }
      );
    }
  }

  // src/container.ts
  function installContainer(_authorize) {
    const _bridgeUrl = window.__truapi_localhost?.url;
    const _webSocketBackend = window.__truapi_websocket_connect__;
    freezeAndDelete(window, "__truapi_websocket_connect__");
    installWebSocketGate(window, _authorize.network, _bridgeUrl, _webSocketBackend);
    installFetchGate(window, _authorize.network);
    installXhrGate(window, _authorize.network);
    installMediaPolicy(window, _authorize.media);
    freezeAndDelete(window, "EventSource");
    freezeAndDelete(window, "WebTransport");
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
    freezeAndDelete(window, "Worker");
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
    const _createElement = document.createElement.bind(document);
    freezeValue(document, "createElement", (tagName, options) => {
      if (tagName.toLowerCase() === "iframe") {
        throw new Error("iframe creation is not allowed");
      }
      return _createElement(tagName, options);
    });
    installWebRtcPolicy(window, _authorize.webRtc);
    reportLockdownFailures();
  }

  // ../../node_modules/@noble/hashes/utils.js
  function isBytes(a) {
    return a instanceof Uint8Array || ArrayBuffer.isView(a) && a.constructor.name === "Uint8Array" && "BYTES_PER_ELEMENT" in a && a.BYTES_PER_ELEMENT === 1;
  }
  function abytes(value, length, title = "") {
    const bytes = isBytes(value);
    const len = value?.length;
    const needsLen = length !== void 0;
    if (!bytes || needsLen && len !== length) {
      const prefix = title && `"${title}" `;
      const ofLen = needsLen ? ` of length ${length}` : "";
      const got = bytes ? `length=${len}` : `type=${typeof value}`;
      const message = prefix + "expected Uint8Array" + ofLen + ", got " + got;
      if (!bytes)
        throw new TypeError(message);
      throw new RangeError(message);
    }
    return value;
  }
  var hasHexBuiltin = /* @__PURE__ */ (() => (
    // @ts-ignore
    typeof Uint8Array.from([]).toHex === "function" && typeof Uint8Array.fromHex === "function"
  ))();
  var hexes = /* @__PURE__ */ Array.from({ length: 256 }, (_, i) => i.toString(16).padStart(2, "0"));
  function bytesToHex(bytes) {
    abytes(bytes);
    if (hasHexBuiltin)
      return bytes.toHex();
    let hex = "";
    for (let i = 0; i < bytes.length; i++) {
      hex += hexes[bytes[i]];
    }
    return hex;
  }
  var asciis = { _0: 48, _9: 57, A: 65, F: 70, a: 97, f: 102 };
  function asciiToBase16(ch) {
    if (ch >= asciis._0 && ch <= asciis._9)
      return ch - asciis._0;
    if (ch >= asciis.A && ch <= asciis.F)
      return ch - (asciis.A - 10);
    if (ch >= asciis.a && ch <= asciis.f)
      return ch - (asciis.a - 10);
    return;
  }
  function hexToBytes(hex) {
    if (typeof hex !== "string")
      throw new TypeError("hex string expected, got " + typeof hex);
    if (hasHexBuiltin) {
      try {
        return Uint8Array.fromHex(hex);
      } catch (error) {
        if (error instanceof SyntaxError)
          throw new RangeError(error.message);
        throw error;
      }
    }
    const hl = hex.length;
    const al = hl / 2;
    if (hl % 2)
      throw new RangeError("hex string expected, got unpadded hex of length " + hl);
    const array = new Uint8Array(al);
    for (let ai = 0, hi = 0; ai < al; ai++, hi += 2) {
      const n1 = asciiToBase16(hex.charCodeAt(hi));
      const n2 = asciiToBase16(hex.charCodeAt(hi + 1));
      if (n1 === void 0 || n2 === void 0) {
        const char = hex[hi] + hex[hi + 1];
        throw new RangeError('hex string expected, got non-hex character "' + char + '" at index ' + hi);
      }
      array[ai] = n1 * 16 + n2;
    }
    return array;
  }
  function concatBytes(...arrays) {
    let sum = 0;
    for (let i = 0; i < arrays.length; i++) {
      const a = arrays[i];
      abytes(a);
      sum += a.length;
    }
    const res = new Uint8Array(sum);
    for (let i = 0, pad = 0; i < arrays.length; i++) {
      const a = arrays[i];
      res.set(a, pad);
      pad += a.length;
    }
    return res;
  }

  // ../../node_modules/neverthrow/dist/index.es.js
  var defaultErrorConfig = {
    withStackTrace: false
  };
  var createNeverThrowError = (message, result, config = defaultErrorConfig) => {
    const data = result.isOk() ? { type: "Ok", value: result.value } : { type: "Err", value: result.error };
    const maybeStack = config.withStackTrace ? new Error().stack : void 0;
    return {
      data,
      message,
      stack: maybeStack
    };
  };
  function __awaiter(thisArg, _arguments, P, generator) {
    function adopt(value) {
      return value instanceof P ? value : new P(function(resolve) {
        resolve(value);
      });
    }
    return new (P || (P = Promise))(function(resolve, reject) {
      function fulfilled(value) {
        try {
          step(generator.next(value));
        } catch (e) {
          reject(e);
        }
      }
      function rejected(value) {
        try {
          step(generator["throw"](value));
        } catch (e) {
          reject(e);
        }
      }
      function step(result) {
        result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
      }
      step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
  }
  function __values(o) {
    var s = typeof Symbol === "function" && Symbol.iterator, m = s && o[s], i = 0;
    if (m) return m.call(o);
    if (o && typeof o.length === "number") return {
      next: function() {
        if (o && i >= o.length) o = void 0;
        return { value: o && o[i++], done: !o };
      }
    };
    throw new TypeError(s ? "Object is not iterable." : "Symbol.iterator is not defined.");
  }
  function __await(v) {
    return this instanceof __await ? (this.v = v, this) : new __await(v);
  }
  function __asyncGenerator(thisArg, _arguments, generator) {
    if (!Symbol.asyncIterator) throw new TypeError("Symbol.asyncIterator is not defined.");
    var g = generator.apply(thisArg, _arguments || []), i, q = [];
    return i = Object.create((typeof AsyncIterator === "function" ? AsyncIterator : Object).prototype), verb("next"), verb("throw"), verb("return", awaitReturn), i[Symbol.asyncIterator] = function() {
      return this;
    }, i;
    function awaitReturn(f) {
      return function(v) {
        return Promise.resolve(v).then(f, reject);
      };
    }
    function verb(n, f) {
      if (g[n]) {
        i[n] = function(v) {
          return new Promise(function(a, b) {
            q.push([n, v, a, b]) > 1 || resume(n, v);
          });
        };
        if (f) i[n] = f(i[n]);
      }
    }
    function resume(n, v) {
      try {
        step(g[n](v));
      } catch (e) {
        settle(q[0][3], e);
      }
    }
    function step(r) {
      r.value instanceof __await ? Promise.resolve(r.value.v).then(fulfill, reject) : settle(q[0][2], r);
    }
    function fulfill(value) {
      resume("next", value);
    }
    function reject(value) {
      resume("throw", value);
    }
    function settle(f, v) {
      if (f(v), q.shift(), q.length) resume(q[0][0], q[0][1]);
    }
  }
  function __asyncDelegator(o) {
    var i, p;
    return i = {}, verb("next"), verb("throw", function(e) {
      throw e;
    }), verb("return"), i[Symbol.iterator] = function() {
      return this;
    }, i;
    function verb(n, f) {
      i[n] = o[n] ? function(v) {
        return (p = !p) ? { value: __await(o[n](v)), done: false } : f ? f(v) : v;
      } : f;
    }
  }
  function __asyncValues(o) {
    if (!Symbol.asyncIterator) throw new TypeError("Symbol.asyncIterator is not defined.");
    var m = o[Symbol.asyncIterator], i;
    return m ? m.call(o) : (o = typeof __values === "function" ? __values(o) : o[Symbol.iterator](), i = {}, verb("next"), verb("throw"), verb("return"), i[Symbol.asyncIterator] = function() {
      return this;
    }, i);
    function verb(n) {
      i[n] = o[n] && function(v) {
        return new Promise(function(resolve, reject) {
          v = o[n](v), settle(resolve, reject, v.done, v.value);
        });
      };
    }
    function settle(resolve, reject, d, v) {
      Promise.resolve(v).then(function(v2) {
        resolve({ value: v2, done: d });
      }, reject);
    }
  }
  var ResultAsync = class _ResultAsync {
    constructor(res) {
      this._promise = res;
    }
    static fromSafePromise(promise) {
      const newPromise = promise.then((value) => new Ok(value));
      return new _ResultAsync(newPromise);
    }
    static fromPromise(promise, errorFn) {
      const newPromise = promise.then((value) => new Ok(value)).catch((e) => new Err(errorFn(e)));
      return new _ResultAsync(newPromise);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    static fromThrowable(fn, errorFn) {
      return (...args) => {
        return new _ResultAsync((() => __awaiter(this, void 0, void 0, function* () {
          try {
            return new Ok(yield fn(...args));
          } catch (error) {
            return new Err(errorFn ? errorFn(error) : error);
          }
        }))());
      };
    }
    static combine(asyncResultList) {
      return combineResultAsyncList(asyncResultList);
    }
    static combineWithAllErrors(asyncResultList) {
      return combineResultAsyncListWithAllErrors(asyncResultList);
    }
    map(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isErr()) {
          return new Err(res.error);
        }
        return new Ok(yield f(res.value));
      })));
    }
    andThrough(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isErr()) {
          return new Err(res.error);
        }
        const newRes = yield f(res.value);
        if (newRes.isErr()) {
          return new Err(newRes.error);
        }
        return new Ok(res.value);
      })));
    }
    andTee(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isErr()) {
          return new Err(res.error);
        }
        try {
          yield f(res.value);
        } catch (e) {
        }
        return new Ok(res.value);
      })));
    }
    orTee(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isOk()) {
          return new Ok(res.value);
        }
        try {
          yield f(res.error);
        } catch (e) {
        }
        return new Err(res.error);
      })));
    }
    mapErr(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isOk()) {
          return new Ok(res.value);
        }
        return new Err(yield f(res.error));
      })));
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    andThen(f) {
      return new _ResultAsync(this._promise.then((res) => {
        if (res.isErr()) {
          return new Err(res.error);
        }
        const newValue = f(res.value);
        return newValue instanceof _ResultAsync ? newValue._promise : newValue;
      }));
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    orElse(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isErr()) {
          return f(res.error);
        }
        return new Ok(res.value);
      })));
    }
    match(ok2, _err) {
      return this._promise.then((res) => res.match(ok2, _err));
    }
    unwrapOr(t) {
      return this._promise.then((res) => res.unwrapOr(t));
    }
    /**
     * @deprecated will be removed in 9.0.0.
     *
     * You can use `safeTry` without this method.
     * @example
     * ```typescript
     * safeTry(async function* () {
     *   const okValue = yield* yourResult
     * })
     * ```
     * Emulates Rust's `?` operator in `safeTry`'s body. See also `safeTry`.
     */
    safeUnwrap() {
      return __asyncGenerator(this, arguments, function* safeUnwrap_1() {
        return yield __await(yield __await(yield* __asyncDelegator(__asyncValues(yield __await(this._promise.then((res) => res.safeUnwrap()))))));
      });
    }
    // Makes ResultAsync implement PromiseLike<Result>
    then(successCallback, failureCallback) {
      return this._promise.then(successCallback, failureCallback);
    }
    [Symbol.asyncIterator]() {
      return __asyncGenerator(this, arguments, function* _a() {
        const result = yield __await(this._promise);
        if (result.isErr()) {
          yield yield __await(errAsync(result.error));
        }
        return yield __await(result.value);
      });
    }
  };
  function errAsync(err2) {
    return new ResultAsync(Promise.resolve(new Err(err2)));
  }
  var fromPromise = ResultAsync.fromPromise;
  var fromSafePromise = ResultAsync.fromSafePromise;
  var fromAsyncThrowable = ResultAsync.fromThrowable;
  var combineResultList = (resultList) => {
    let acc = ok([]);
    for (const result of resultList) {
      if (result.isErr()) {
        acc = err(result.error);
        break;
      } else {
        acc.map((list) => list.push(result.value));
      }
    }
    return acc;
  };
  var combineResultAsyncList = (asyncResultList) => ResultAsync.fromSafePromise(Promise.all(asyncResultList)).andThen(combineResultList);
  var combineResultListWithAllErrors = (resultList) => {
    let acc = ok([]);
    for (const result of resultList) {
      if (result.isErr() && acc.isErr()) {
        acc.error.push(result.error);
      } else if (result.isErr() && acc.isOk()) {
        acc = err([result.error]);
      } else if (result.isOk() && acc.isOk()) {
        acc.value.push(result.value);
      }
    }
    return acc;
  };
  var combineResultAsyncListWithAllErrors = (asyncResultList) => ResultAsync.fromSafePromise(Promise.all(asyncResultList)).andThen(combineResultListWithAllErrors);
  var Result;
  (function(Result3) {
    function fromThrowable2(fn, errorFn) {
      return (...args) => {
        try {
          const result = fn(...args);
          return ok(result);
        } catch (e) {
          return err(errorFn ? errorFn(e) : e);
        }
      };
    }
    Result3.fromThrowable = fromThrowable2;
    function combine(resultList) {
      return combineResultList(resultList);
    }
    Result3.combine = combine;
    function combineWithAllErrors(resultList) {
      return combineResultListWithAllErrors(resultList);
    }
    Result3.combineWithAllErrors = combineWithAllErrors;
  })(Result || (Result = {}));
  function ok(value) {
    return new Ok(value);
  }
  function err(err2) {
    return new Err(err2);
  }
  var Ok = class {
    constructor(value) {
      this.value = value;
    }
    isOk() {
      return true;
    }
    isErr() {
      return !this.isOk();
    }
    map(f) {
      return ok(f(this.value));
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    mapErr(_f) {
      return ok(this.value);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    andThen(f) {
      return f(this.value);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    andThrough(f) {
      return f(this.value).map((_value) => this.value);
    }
    andTee(f) {
      try {
        f(this.value);
      } catch (e) {
      }
      return ok(this.value);
    }
    orTee(_f) {
      return ok(this.value);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    orElse(_f) {
      return ok(this.value);
    }
    asyncAndThen(f) {
      return f(this.value);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    asyncAndThrough(f) {
      return f(this.value).map(() => this.value);
    }
    asyncMap(f) {
      return ResultAsync.fromSafePromise(f(this.value));
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    unwrapOr(_v) {
      return this.value;
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    match(ok2, _err) {
      return ok2(this.value);
    }
    safeUnwrap() {
      const value = this.value;
      return (function* () {
        return value;
      })();
    }
    _unsafeUnwrap(_) {
      return this.value;
    }
    _unsafeUnwrapErr(config) {
      throw createNeverThrowError("Called `_unsafeUnwrapErr` on an Ok", this, config);
    }
    // eslint-disable-next-line @typescript-eslint/no-this-alias, require-yield
    *[Symbol.iterator]() {
      return this.value;
    }
  };
  var Err = class {
    constructor(error) {
      this.error = error;
    }
    isOk() {
      return false;
    }
    isErr() {
      return !this.isOk();
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    map(_f) {
      return err(this.error);
    }
    mapErr(f) {
      return err(f(this.error));
    }
    andThrough(_f) {
      return err(this.error);
    }
    andTee(_f) {
      return err(this.error);
    }
    orTee(f) {
      try {
        f(this.error);
      } catch (e) {
      }
      return err(this.error);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    andThen(_f) {
      return err(this.error);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    orElse(f) {
      return f(this.error);
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    asyncAndThen(_f) {
      return errAsync(this.error);
    }
    asyncAndThrough(_f) {
      return errAsync(this.error);
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    asyncMap(_f) {
      return errAsync(this.error);
    }
    unwrapOr(v) {
      return v;
    }
    match(_ok, err2) {
      return err2(this.error);
    }
    safeUnwrap() {
      const error = this.error;
      return (function* () {
        yield err(error);
        throw new Error("Do not use this generator out of `safeTry`");
      })();
    }
    _unsafeUnwrap(config) {
      throw createNeverThrowError("Called `_unsafeUnwrap` on an Err", this, config);
    }
    _unsafeUnwrapErr(_) {
      return this.error;
    }
    *[Symbol.iterator]() {
      const self = this;
      yield self;
      return self;
    }
  };
  var fromThrowable = Result.fromThrowable;

  // ../packages/truapi/dist/scale.js
  var scale_exports = {};
  __export(scale_exports, {
    Bytes: () => Bytes,
    CallError: () => CallError,
    Enum: () => Enum,
    Hex: () => Hex,
    Option: () => Option,
    OptionBool: () => OptionBool,
    Result: () => Result2,
    Status: () => Status,
    Struct: () => Struct,
    TaggedUnion: () => TaggedUnion,
    Tuple: () => Tuple,
    Vector: () => Vector,
    _void: () => _void,
    bool: () => bool,
    bytesToHex: () => bytesToHex2,
    compact: () => compact,
    hexToBytes: () => hexToBytes2,
    i128: () => i128,
    i16: () => i16,
    i32: () => i32,
    i64: () => i64,
    i8: () => i8,
    indexedTaggedUnion: () => indexedTaggedUnion,
    lazy: () => lazy,
    str: () => str,
    toHexString: () => toHexString,
    u128: () => u128,
    u16: () => u16,
    u32: () => u32,
    u64: () => u64,
    u8: () => u8
  });

  // ../../node_modules/scale-ts/dist/scale-ts.js
  var __defProp2 = Object.defineProperty;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp2(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField = (obj, key, value) => {
    __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
    return value;
  };
  var HEX_MAP = {
    0: 0,
    1: 1,
    2: 2,
    3: 3,
    4: 4,
    5: 5,
    6: 6,
    7: 7,
    8: 8,
    9: 9,
    a: 10,
    b: 11,
    c: 12,
    d: 13,
    e: 14,
    f: 15,
    A: 10,
    B: 11,
    C: 12,
    D: 13,
    E: 14,
    F: 15
  };
  function fromHex(hexString) {
    const isOdd = hexString.length % 2;
    const base = (hexString[1] === "x" ? 2 : 0) + isOdd;
    const nBytes = (hexString.length - base) / 2 + isOdd;
    const bytes = new Uint8Array(nBytes);
    if (isOdd)
      bytes[0] = 0 | HEX_MAP[hexString[2]];
    for (let i = 0; i < nBytes; ) {
      const idx = base + i * 2;
      const a = HEX_MAP[hexString[idx]];
      const b = HEX_MAP[hexString[idx + 1]];
      bytes[isOdd + i++] = a << 4 | b;
    }
    return bytes;
  }
  var InternalUint8Array = class extends Uint8Array {
    constructor(buffer) {
      super(buffer);
      __publicField(this, "i", 0);
      __publicField(this, "v");
      this.v = new DataView(buffer);
    }
  };
  var toInternalBytes = (fn) => (buffer) => fn(buffer instanceof InternalUint8Array ? buffer : new InternalUint8Array(buffer instanceof Uint8Array ? buffer.buffer : typeof buffer === "string" ? fromHex(buffer).buffer : buffer));
  var mergeUint8 = (inputs) => {
    const len = inputs.length;
    let totalLen = 0;
    for (let i = 0; i < len; i++)
      totalLen += inputs[i].length;
    const result = new Uint8Array(totalLen);
    for (let idx = 0, at = 0; idx < len; idx++) {
      const current = inputs[idx];
      result.set(current, at);
      at += current.byteLength;
    }
    return result;
  };
  function mapObject(input, mapper) {
    const keys = Object.keys(input);
    const len = keys.length;
    const result = {};
    for (let i = 0; i < len; i++) {
      const key = keys[i];
      result[key] = mapper(input[key], key);
    }
    return result;
  }
  var createDecoder = toInternalBytes;
  var createCodec = (encoder, decoder) => {
    const result = [encoder, decoder];
    result.enc = encoder;
    result.dec = decoder;
    return result;
  };
  var enhanceEncoder = (encoder, mapper) => (value) => encoder(mapper(value));
  var enhanceDecoder = (decoder, mapper) => (value) => mapper(decoder(value));
  var enhanceCodec = ([encoder, decoder], toFrom, fromTo) => createCodec(enhanceEncoder(encoder, toFrom), enhanceDecoder(decoder, fromTo));
  function decodeInt(nBytes, getter2) {
    return toInternalBytes((bytes) => {
      const result = bytes.v[getter2](bytes.i, true);
      bytes.i += nBytes;
      return result;
    });
  }
  function encodeInt(nBytes, setter) {
    return (input) => {
      const result = new Uint8Array(nBytes);
      const dv = new DataView(result.buffer);
      dv[setter](0, input, true);
      return result;
    };
  }
  function intCodec(nBytes, getter2, setter) {
    return createCodec(encodeInt(nBytes, setter), decodeInt(nBytes, getter2));
  }
  var u8 = intCodec(1, "getUint8", "setUint8");
  var u16 = intCodec(2, "getUint16", "setUint16");
  var u32 = intCodec(4, "getUint32", "setUint32");
  var u64 = intCodec(8, "getBigUint64", "setBigUint64");
  var i8 = intCodec(1, "getInt8", "setInt8");
  var i16 = intCodec(2, "getInt16", "setInt16");
  var i32 = intCodec(4, "getInt32", "setInt32");
  var i64 = intCodec(8, "getBigInt64", "setBigInt64");
  var x128Enc = (value) => {
    const result = new Uint8Array(16);
    const dv = new DataView(result.buffer);
    dv.setBigInt64(0, value, true);
    dv.setBigInt64(8, value >> 64n, true);
    return result;
  };
  var create128Dec = (method) => toInternalBytes((input) => {
    const { v, i } = input;
    const right = v.getBigUint64(i, true);
    const left = v[method](i + 8, true);
    input.i += 16;
    return left << 64n | right;
  });
  var u128 = createCodec(x128Enc, create128Dec("getBigUint64"));
  var i128 = createCodec(x128Enc, create128Dec("getBigInt64"));
  var x256Enc = (value) => {
    const result = new Uint8Array(32);
    const dv = new DataView(result.buffer);
    dv.setBigInt64(0, value, true);
    dv.setBigInt64(8, value >> 64n, true);
    dv.setBigInt64(16, value >> 128n, true);
    dv.setBigInt64(24, value >> 192n, true);
    return result;
  };
  var create256Dec = (method) => toInternalBytes((input) => {
    let result = input.v.getBigUint64(input.i, true);
    input.i += 8;
    result |= input.v.getBigUint64(input.i, true) << 64n;
    input.i += 8;
    result |= input.v.getBigUint64(input.i, true) << 128n;
    input.i += 8;
    result |= input.v[method](input.i, true) << 192n;
    input.i += 8;
    return result;
  });
  var u256 = createCodec(x256Enc, create256Dec("getBigUint64"));
  var i256 = createCodec(x256Enc, create256Dec("getBigInt64"));
  var bool = enhanceCodec(u8, (value) => value ? 1 : 0, Boolean);
  var decoders = [u8[1], u16[1], u32[1]];
  var compactDec = toInternalBytes((bytes) => {
    const init = bytes[bytes.i];
    const kind = init & 3;
    if (kind < 3)
      return decoders[kind](bytes) >>> 2;
    const nBytes = (init >>> 2) + 4;
    bytes.i++;
    let result = 0n;
    const nU64 = nBytes / 8 | 0;
    let shift = 0n;
    for (let i = 0; i < nU64; i++) {
      result = u64[1](bytes) << shift | result;
      shift += 64n;
    }
    let nReminders = nBytes % 8;
    if (nReminders > 3) {
      result = BigInt(u32[1](bytes)) << shift | result;
      shift += 32n;
      nReminders -= 4;
    }
    if (nReminders > 1) {
      result = BigInt(u16[1](bytes)) << shift | result;
      shift += 16n;
      nReminders -= 2;
    }
    if (nReminders)
      result = BigInt(u8[1](bytes)) << shift | result;
    return result;
  });
  var MIN_U64 = 1n << 56n;
  var MIN_U32 = 1 << 24;
  var MIN_U16 = 256;
  var U32_MASK = 4294967295n;
  var SINGLE_BYTE_MODE_LIMIT = 1 << 6;
  var TWO_BYTE_MODE_LIMIT = 1 << 14;
  var FOUR_BYTE_MODE_LIMIT = 1 << 30;
  var compactEnc = (input) => {
    if (input < 0)
      throw new Error(`Wrong compact input (${input})`);
    const nInput = Number(input) << 2;
    if (input < SINGLE_BYTE_MODE_LIMIT)
      return u8[0](nInput);
    if (input < TWO_BYTE_MODE_LIMIT)
      return u16[0](nInput | 1);
    if (input < FOUR_BYTE_MODE_LIMIT)
      return u32[0](nInput | 2);
    let buffers = [new Uint8Array(1)];
    let bigValue = BigInt(input);
    while (bigValue >= MIN_U64) {
      buffers.push(u64[0](bigValue));
      bigValue >>= 64n;
    }
    if (bigValue >= MIN_U32) {
      buffers.push(u32[0](Number(bigValue & U32_MASK)));
      bigValue >>= 32n;
    }
    let smValue = Number(bigValue);
    if (smValue >= MIN_U16) {
      buffers.push(u16[0](smValue));
      smValue >>= 16;
    }
    smValue && buffers.push(u8[0](smValue));
    const result = mergeUint8(buffers);
    result[0] = result.length - 5 << 2 | 3;
    return result;
  };
  var compact = createCodec(compactEnc, compactDec);
  var textEncoder = new TextEncoder();
  var strEnc = (str2) => {
    const val = textEncoder.encode(str2);
    return mergeUint8([compact.enc(val.length), val]);
  };
  var textDecoder = new TextDecoder();
  var strDec = toInternalBytes((bytes) => {
    let nElements = compact.dec(bytes);
    const dv = new DataView(bytes.buffer, bytes.i, nElements);
    bytes.i += nElements;
    return textDecoder.decode(dv);
  });
  var str = createCodec(strEnc, strDec);
  var noop = () => {
  };
  var emptyArr = new Uint8Array(0);
  var _void = createCodec(() => emptyArr, noop);
  var BytesEnc = (nBytes) => nBytes === void 0 ? (bytes) => mergeUint8([compact.enc(bytes.length), bytes]) : (bytes) => bytes.length === nBytes ? bytes : bytes.slice(0, nBytes);
  var BytesDec = (nBytes) => toInternalBytes((bytes) => {
    const len = nBytes === void 0 ? compact.dec(bytes) : nBytes !== Infinity ? nBytes : bytes.byteLength - bytes.i;
    const result = new Uint8Array(bytes.buffer.slice(bytes.i, bytes.i + len));
    bytes.i += len;
    return result;
  });
  var Bytes = (nBytes) => createCodec(BytesEnc(nBytes), BytesDec(nBytes));
  Bytes.enc = BytesEnc;
  Bytes.dec = BytesDec;
  var enumEnc = (inner, x) => {
    const keys = Object.keys(inner);
    const mappedKeys = new Map(x?.map((actualIdx, idx) => [keys[idx], actualIdx]) ?? keys.map((key, idx) => [key, idx]));
    const getKey = (key) => mappedKeys.get(key);
    return ({ tag, value }) => mergeUint8([u8.enc(getKey(tag)), inner[tag](value)]);
  };
  var enumDec = (inner, x) => {
    const keys = Object.keys(inner);
    const mappedKeys = new Map(x?.map((actualIdx, idx) => [actualIdx, keys[idx]]) ?? keys.map((key, idx) => [idx, key]));
    return toInternalBytes((bytes) => {
      const idx = u8.dec(bytes);
      const tag = mappedKeys.get(idx);
      const innerDecoder = inner[tag];
      return {
        tag,
        value: innerDecoder(bytes)
      };
    });
  };
  var Enum = (inner, ...args) => createCodec(enumEnc(mapObject(inner, ([encoder]) => encoder), ...args), enumDec(mapObject(inner, ([, decoder]) => decoder), ...args));
  Enum.enc = enumEnc;
  Enum.dec = enumDec;
  var OptionDec = (inner) => toInternalBytes((bytes) => u8[1](bytes) > 0 ? inner(bytes) : void 0);
  var OptionEnc = (inner) => (value) => {
    const result = new Uint8Array(1);
    if (value === void 0)
      return result;
    result[0] = 1;
    return mergeUint8([result, inner(value)]);
  };
  var Option = (inner) => createCodec(OptionEnc(inner[0]), OptionDec(inner[1]));
  Option.enc = OptionEnc;
  Option.dec = OptionDec;
  var ResultDec = (okDecoder, koDecoder) => toInternalBytes((bytes) => {
    const success = u8[1](bytes) === 0;
    const decoder = success ? okDecoder : koDecoder;
    const value = decoder(bytes);
    return { success, value };
  });
  var ResultEnc = (okEncoder, koEncoder) => ({ success, value }) => mergeUint8([
    u8[0](success ? 0 : 1),
    (success ? okEncoder : koEncoder)(value)
  ]);
  var Result2 = (okCodec, koCodec) => createCodec(ResultEnc(okCodec[0], koCodec[0]), ResultDec(okCodec[1], koCodec[1]));
  Result2.dec = ResultDec;
  Result2.enc = ResultEnc;
  var TupleDec = (...decoders2) => toInternalBytes((bytes) => decoders2.map((decoder) => decoder(bytes)));
  var TupleEnc = (...encoders) => (values) => mergeUint8(encoders.map((enc, idx) => enc(values[idx])));
  var Tuple = (...codecs) => createCodec(TupleEnc(...codecs.map(([encoder]) => encoder)), TupleDec(...codecs.map(([, decoder]) => decoder)));
  Tuple.enc = TupleEnc;
  Tuple.dec = TupleDec;
  var StructEnc = (encoders) => {
    const keys = Object.keys(encoders);
    return enhanceEncoder(Tuple.enc(...Object.values(encoders)), (input) => keys.map((k) => input[k]));
  };
  var StructDec = (decoders2) => {
    const keys = Object.keys(decoders2);
    return enhanceDecoder(Tuple.dec(...Object.values(decoders2)), (tuple) => Object.fromEntries(tuple.map((value, idx) => [keys[idx], value])));
  };
  var Struct = (codecs) => createCodec(StructEnc(mapObject(codecs, (x) => x[0])), StructDec(mapObject(codecs, (x) => x[1])));
  Struct.enc = StructEnc;
  Struct.dec = StructDec;
  var VectorEnc = (inner, size) => size >= 0 ? (value) => mergeUint8(value.map(inner)) : (value) => mergeUint8([compact.enc(value.length), mergeUint8(value.map(inner))]);
  var VectorDec = (getter2, size) => toInternalBytes((bytes) => {
    const nElements = size >= 0 ? size : compact.dec(bytes);
    const result = new Array(nElements);
    for (let i = 0; i < nElements; i++) {
      result[i] = getter2(bytes);
    }
    return result;
  });
  var Vector = (inner, size) => createCodec(VectorEnc(inner[0], size), VectorDec(inner[1], size));
  Vector.enc = VectorEnc;
  Vector.dec = VectorDec;

  // ../packages/truapi/dist/scale.js
  var OptionBool = enhanceCodec(u8, (value) => value === void 0 ? 0 : value ? 1 : 2, (byte) => {
    switch (byte) {
      case 0:
        return void 0;
      case 1:
        return true;
      case 2:
        return false;
      default:
        throw new Error(`Unknown OptionBool byte: ${byte}. Expected 0, 1, or 2.`);
    }
  });
  function toHexString(value) {
    if (!value.startsWith("0x")) {
      throw new Error(`Expected hex string starting with 0x, got: ${value.slice(0, 20)}`);
    }
    return value;
  }
  function bytesToHex2(bytes) {
    return `0x${bytesToHex(bytes)}`;
  }
  function hexToBytes2(hex) {
    return hexToBytes(hex.startsWith("0x") ? hex.slice(2) : hex);
  }
  function Hex(length) {
    return enhanceCodec(Bytes(length), hexToBytes2, bytesToHex2);
  }
  function TaggedUnion(inner) {
    return Enum(inner);
  }
  function CallError(domain) {
    return TaggedUnion({
      Domain: domain,
      Denied: _void,
      Unsupported: _void,
      MalformedFrame: Struct({ reason: str }),
      HostFailure: Struct({ reason: str }),
      // Appended last, mirroring the Rust enum: the variants above keep their
      // SCALE indices.
      Cancelled: _void
    });
  }
  function Status(...variants) {
    return enhanceCodec(u8, (value) => {
      const index = variants.indexOf(value);
      if (index === -1) {
        throw new Error(`Unknown status value: ${String(value)}`);
      }
      return index;
    }, (index) => {
      const value = variants[index];
      if (value === void 0) {
        throw new Error(`Unknown status index: ${index}`);
      }
      return value;
    });
  }
  function lazy(factory) {
    let resolved;
    const get = () => resolved ?? (resolved = factory());
    return createCodec((value) => get().enc(value), (input) => get().dec(input));
  }
  function indexedTaggedUnion(variants) {
    const byIndex = /* @__PURE__ */ new Map();
    for (const [tag, [index, codec]] of Object.entries(variants)) {
      if (!Number.isInteger(index) || index < 0 || index > 255) {
        throw new Error(`Invalid enum discriminant for ${tag}: ${index}`);
      }
      if (byIndex.has(index)) {
        throw new Error(`Duplicate enum discriminant: ${index}`);
      }
      byIndex.set(index, [tag, codec]);
    }
    return createCodec((value) => {
      const variant = variants[value.tag];
      if (!variant) {
        throw new Error(`Unknown enum variant: ${value.tag}`);
      }
      const [index, codec] = variant;
      const payload = codec.enc(value.value);
      const out = new Uint8Array(payload.length + 1);
      out[0] = index;
      out.set(payload, 1);
      return out;
    }, createDecoder((input) => {
      const index = u8.dec(input);
      const variant = byIndex.get(index);
      if (!variant) {
        throw new Error(`Unknown enum discriminant: ${index}`);
      }
      const [tag, codec] = variant;
      return { tag, value: codec.dec(input) };
    }));
  }

  // ../packages/truapi/dist/transport.js
  var MESSAGE_TYPE_REQUEST = 0;
  var MESSAGE_TYPE_RESPONSE = 1;
  function encodeWireMessage(message) {
    const { traitId, methodId, messageType } = message.payload;
    if (!Number.isInteger(traitId) || traitId < 0 || traitId > 255) {
      return err(new Error(`Invalid wire trait discriminant: ${traitId}`));
    }
    if (!Number.isInteger(methodId) || methodId < 0 || methodId > 255) {
      return err(new Error(`Invalid wire method discriminant: ${methodId}`));
    }
    if (!Number.isInteger(messageType) || messageType < 0 || messageType > 255) {
      return err(new Error(`Invalid wire message type: ${messageType}`));
    }
    return ok(concatBytes(str.enc(message.requestId), u8.enc(traitId), u8.enc(methodId), u8.enc(messageType), message.payload.value));
  }

  // ../packages/truapi/dist/generated/types.js
  var AccountId = lazy(() => Hex(32));
  var ActionTrigger = lazy(() => Struct({ messageId: str, actionId: str, payload: Option(Hex()) }));
  var AllocatableResource = lazy(() => TaggedUnion({ StatementStoreAllowance: _void, BulletinAllowance: _void, SmartContractAllowance: DerivationIndex, AutoSigning: _void }));
  var AllocationOutcome = lazy(() => Status("Allocated", "Rejected", "NotAvailable"));
  var Arrangement = lazy(() => Status("Start", "End", "Center", "SpaceBetween", "SpaceAround", "SpaceEvenly"));
  var Background = lazy(() => Struct({ color: ColorToken, shape: Option(Shape) }));
  var Balance = lazy(() => u128);
  var BlendingMode = lazy(() => Status("Normal", "Multiply", "Screen", "Overlay", "Darken", "Lighten", "ColorDodge", "ColorBurn", "HardLight", "SoftLight", "Difference", "Exclusion", "Hue", "Saturation", "Color", "Luminosity"));
  var BorderStyle = lazy(() => Struct({ width: Size, color: ColorToken, shape: Option(Shape) }));
  var BoxProps = lazy(() => Struct({ contentAlignment: Option(ContentAlignment) }));
  var ButtonProps = lazy(() => Struct({ text: str, variant: Option(ButtonVariant), enabled: OptionBool, loading: OptionBool, clickAction: Option(str) }));
  var ButtonVariant = lazy(() => Status("Primary", "Secondary", "Text"));
  var Bytes32 = lazy(() => Hex(32));
  var ChainIdentifier = lazy(() => Status("Relay", "AssetHub", "People", "Bulletin"));
  var ChatAction = lazy(() => Struct({ actionId: str, title: str }));
  var ChatActionLayout = lazy(() => Status("Column", "Grid"));
  var ChatActionPayload = lazy(() => TaggedUnion({ MessagePosted: ChatMessageContent, ActionTriggered: ActionTrigger, Command: ChatCommand }));
  var ChatActions = lazy(() => Struct({ text: Option(str), actions: Vector(ChatAction), layout: ChatActionLayout }));
  var ChatBotRegistrationStatus = lazy(() => Status("New", "Exists"));
  var ChatCommand = lazy(() => Struct({ command: str, payload: str }));
  var ChatCustomMessage = lazy(() => Struct({ messageType: str, payload: Hex() }));
  var ChatFile = lazy(() => Struct({ url: str, fileName: str, mimeType: str, sizeBytes: u64, text: Option(str) }));
  var ChatMedia = lazy(() => Struct({ url: str }));
  var ChatMessageContent = lazy(() => TaggedUnion({ Text: Struct({ text: str }), RichText: ChatRichText, Actions: ChatActions, File: ChatFile, Reaction: ChatReaction, ReactionRemoved: ChatReaction, Custom: ChatCustomMessage }));
  var ChatReaction = lazy(() => Struct({ messageId: str, emoji: str }));
  var ChatRichText = lazy(() => Struct({ text: Option(str), media: Vector(ChatMedia) }));
  var ChatRoom = lazy(() => Struct({ roomId: str, participatingAs: ChatRoomParticipation }));
  var ChatRoomParticipation = lazy(() => Status("RoomHost", "Bot"));
  var ChatRoomRegistrationStatus = lazy(() => Status("New", "Exists"));
  var CoinPaymentBalance = lazy(() => u32);
  var CoinPaymentCheque = lazy(() => Struct({ id: CoinPaymentReceivable, amount: CoinPaymentBalance, encryptedSecrets: Hex() }));
  var CoinPaymentClearingReference = lazy(() => Struct({ root: CoinPaymentMerkleRoot, leaves: Vector(Tuple(CoinPaymentCoinagePubKey, CoinPaymentTransactionHash)) }));
  var CoinPaymentCoinagePubKey = lazy(() => Hex(32));
  var CoinPaymentError = lazy(() => Status("BalanceLow", "Denied", "BadCoins", "SnipedCoins", "PurseNotFound", "ReceivableNotFound", "UnsupportedChannel", "UserAgentCapabilityUnavailable", "Internal"));
  var CoinPaymentMerkleRoot = lazy(() => Hex(32));
  var CoinPaymentProductId = lazy(() => str);
  var CoinPaymentPurseId = lazy(() => u32);
  var CoinPaymentPurseInfo = lazy(() => Struct({ name: str, created: CoinPaymentTimestamp, creator: CoinPaymentProductId, balance: CoinPaymentBalance }));
  var CoinPaymentReceivable = lazy(() => Hex(32));
  var CoinPaymentStatus = lazy(() => TaggedUnion({ Clearing: Struct({ clearing: CoinPaymentBalance, cleared: CoinPaymentBalance }), Failed: Struct({ error: CoinPaymentError, cleared: CoinPaymentBalance, reference: CoinPaymentClearingReference }), Done: Struct({ cleared: CoinPaymentBalance, reference: CoinPaymentClearingReference }) }));
  var CoinPaymentTimestamp = lazy(() => u64);
  var CoinPaymentTransactionHash = lazy(() => Hex(32));
  var CoinPaymentTransmissionChannel = lazy(() => TaggedUnion({ Standard: Struct({ sssTopic: Hex(32) }) }));
  var ColorToken = lazy(() => Status("FgPrimary", "FgSecondary", "FgTertiary", "BgSurfaceMain", "BgSurfaceContainer", "BgSurfaceNested", "FgSuccess", "FgError", "FgWarning"));
  var ColumnProps = lazy(() => Struct({ horizontalAlignment: Option(HorizontalAlignment), verticalArrangement: Option(Arrangement) }));
  var ContentAlignment = lazy(() => Status("TopStart", "TopCenter", "TopEnd", "CenterStart", "Center", "CenterEnd", "BottomStart", "BottomCenter", "BottomEnd"));
  var ContextualAlias = lazy(() => Struct({ context: Hex(32), alias: Hex() }));
  var DerivationIndex = lazy(() => TaggedUnion({ Index: u32, Raw: Hex(32) }));
  var Dimensions = lazy(() => Struct({ top: Size, end: Size, bottom: Option(Size), start: Option(Size) }));
  var Effect = lazy(() => Status("Rainbow"));
  var EffectProps = lazy(() => Struct({ effect: Effect }));
  var GenericError = lazy(() => Struct({ reason: str }));
  var GenesisHash = lazy(() => Hex(32));
  var HorizontalAlignment = lazy(() => Status("Start", "Center", "End"));
  var VersionedHostAccountConnectionStatusSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostAccountConnectionStatusSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountConnectionStatusSubscribeItem] }));
  var VersionedHostAccountConnectionStatusSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostAccountCreateProofError = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountCreateProofError] }));
  var VersionedHostAccountCreateProofRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountCreateProofRequest] }));
  var VersionedHostAccountCreateProofResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountCreateProofResponse] }));
  var VersionedHostAccountGetAliasError = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountGetAliasError] }));
  var VersionedHostAccountGetAliasRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountGetAliasRequest] }));
  var VersionedHostAccountGetAliasResponse = lazy(() => indexedTaggedUnion({ V1: [0, ContextualAlias] }));
  var VersionedHostAccountGetError = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountGetError] }));
  var VersionedHostAccountGetRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountGetRequest] }));
  var VersionedHostAccountGetResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountGetResponse] }));
  var VersionedHostAccountListRingVrfKeysError = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountListRingVrfKeysError] }));
  var VersionedHostAccountListRingVrfKeysRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountListRingVrfKeysRequest] }));
  var VersionedHostAccountListRingVrfKeysResponse = lazy(() => indexedTaggedUnion({ V1: [0, Vector(RegisteredRingVrfKey)] }));
  var VersionedHostAccountRegisterRingVrfKeyError = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountRegisterRingVrfKeyError] }));
  var VersionedHostAccountRegisterRingVrfKeyRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountRegisterRingVrfKeyRequest] }));
  var VersionedHostAccountRegisterRingVrfKeyResponse = lazy(() => indexedTaggedUnion({ V1: [0, RingVrfPublicKey] }));
  var VersionedHostAccountRingVrfSignError = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountRingVrfSignError] }));
  var VersionedHostAccountRingVrfSignRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountRingVrfSignRequest] }));
  var VersionedHostAccountRingVrfSignResponse = lazy(() => indexedTaggedUnion({ V1: [0, Hex()] }));
  var VersionedHostAccountSignVrfError = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountSignVrfError] }));
  var VersionedHostAccountSignVrfRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountSignVrfRequest] }));
  var VersionedHostAccountSignVrfResponse = lazy(() => indexedTaggedUnion({ V1: [0, VrfSignature] }));
  var VersionedHostChatActionSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostChatActionSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, HostChatActionSubscribeItem] }));
  var VersionedHostChatActionSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostChatCreateRoomError = lazy(() => indexedTaggedUnion({ V1: [0, HostChatCreateRoomError] }));
  var VersionedHostChatCreateRoomRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostChatCreateRoomRequest] }));
  var VersionedHostChatCreateRoomResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostChatCreateRoomResponse] }));
  var VersionedHostChatListSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostChatListSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, HostChatListSubscribeItem] }));
  var VersionedHostChatListSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostChatPostMessageError = lazy(() => indexedTaggedUnion({ V1: [0, HostChatPostMessageError] }));
  var VersionedHostChatPostMessageRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostChatPostMessageRequest] }));
  var VersionedHostChatPostMessageResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostChatPostMessageResponse] }));
  var VersionedHostChatRegisterBotError = lazy(() => indexedTaggedUnion({ V1: [0, HostChatRegisterBotError] }));
  var VersionedHostChatRegisterBotRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostChatRegisterBotRequest] }));
  var VersionedHostChatRegisterBotResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostChatRegisterBotResponse] }));
  var VersionedHostCoinPaymentCreateChequeError = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentError] }));
  var VersionedHostCoinPaymentCreateChequeRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentCreateChequeRequest] }));
  var VersionedHostCoinPaymentCreateChequeResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentCreateChequeResponse] }));
  var VersionedHostCoinPaymentCreatePurseError = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentError] }));
  var VersionedHostCoinPaymentCreatePurseRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentCreatePurseRequest] }));
  var VersionedHostCoinPaymentCreatePurseResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentCreatePurseResponse] }));
  var VersionedHostCoinPaymentCreateReceivableError = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentError] }));
  var VersionedHostCoinPaymentCreateReceivableRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentCreateReceivableRequest] }));
  var VersionedHostCoinPaymentCreateReceivableResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentCreateReceivableResponse] }));
  var VersionedHostCoinPaymentDeletePurseError = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentError] }));
  var VersionedHostCoinPaymentDeletePurseItem = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentStatus] }));
  var VersionedHostCoinPaymentDeletePurseRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentDeletePurseRequest] }));
  var VersionedHostCoinPaymentDepositError = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentError] }));
  var VersionedHostCoinPaymentDepositItem = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentStatus] }));
  var VersionedHostCoinPaymentDepositRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentDepositRequest] }));
  var VersionedHostCoinPaymentListenForError = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentError] }));
  var VersionedHostCoinPaymentListenForItem = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentListenForItem] }));
  var VersionedHostCoinPaymentListenForRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentListenForRequest] }));
  var VersionedHostCoinPaymentQueryPurseError = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentError] }));
  var VersionedHostCoinPaymentQueryPurseRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentQueryPurseRequest] }));
  var VersionedHostCoinPaymentQueryPurseResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentQueryPurseResponse] }));
  var VersionedHostCoinPaymentRebalancePurseError = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentError] }));
  var VersionedHostCoinPaymentRebalancePurseItem = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentStatus] }));
  var VersionedHostCoinPaymentRebalancePurseRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentRebalancePurseRequest] }));
  var VersionedHostCoinPaymentRefundError = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentError] }));
  var VersionedHostCoinPaymentRefundItem = lazy(() => indexedTaggedUnion({ V1: [0, CoinPaymentStatus] }));
  var VersionedHostCoinPaymentRefundRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostCoinPaymentRefundRequest] }));
  var VersionedHostCreateTransactionError = lazy(() => indexedTaggedUnion({ V1: [0, HostCreateTransactionError] }));
  var VersionedHostCreateTransactionRequest = lazy(() => indexedTaggedUnion({ V1: [0, ProductAccountTxPayload] }));
  var VersionedHostCreateTransactionResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostCreateTransactionResponse] }));
  var VersionedHostCreateTransactionWithLegacyAccountError = lazy(() => indexedTaggedUnion({ V1: [0, HostCreateTransactionError] }));
  var VersionedHostCreateTransactionWithLegacyAccountRequest = lazy(() => indexedTaggedUnion({ V1: [0, LegacyAccountTxPayload] }));
  var VersionedHostCreateTransactionWithLegacyAccountResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostCreateTransactionWithLegacyAccountResponse] }));
  var VersionedHostDeriveEntropyError = lazy(() => indexedTaggedUnion({ V1: [0, HostDeriveEntropyError] }));
  var VersionedHostDeriveEntropyRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostDeriveEntropyRequest] }));
  var VersionedHostDeriveEntropyResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostDeriveEntropyResponse] }));
  var VersionedHostDevicePermissionError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostDevicePermissionRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostDevicePermissionRequest] }));
  var VersionedHostDevicePermissionResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostDevicePermissionResponse] }));
  var VersionedHostFeatureSupportedError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostFeatureSupportedRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostFeatureSupportedRequest] }));
  var VersionedHostFeatureSupportedResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostFeatureSupportedResponse] }));
  var VersionedHostGetLegacyAccountsError = lazy(() => indexedTaggedUnion({ V1: [0, HostAccountGetError] }));
  var VersionedHostGetLegacyAccountsRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostGetLegacyAccountsResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostGetLegacyAccountsResponse] }));
  var VersionedHostGetProductContextError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostGetProductContextRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostGetProductContextResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostGetProductContextResponse] }));
  var VersionedHostGetUserIdError = lazy(() => indexedTaggedUnion({ V1: [0, HostGetUserIdError] }));
  var VersionedHostGetUserIdRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostGetUserIdResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostGetUserIdResponse] }));
  var VersionedHostHandshakeError = lazy(() => indexedTaggedUnion({ V1: [0, HostHandshakeError] }));
  var VersionedHostHandshakeRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostHandshakeRequest] }));
  var VersionedHostHandshakeResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var HostInfo = lazy(() => Struct({ platform: HostPlatform, name: str, version: str }));
  var VersionedHostInfoError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostInfoRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostInfoResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostInfo] }));
  var VersionedHostLocalStorageChangeItem = lazy(() => indexedTaggedUnion({ V1: [0, HostLocalStorageChangeItem] }));
  var VersionedHostLocalStorageClearError = lazy(() => indexedTaggedUnion({ V1: [0, V01HostLocalStorageReadError] }));
  var VersionedHostLocalStorageClearRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostLocalStorageClearRequest] }));
  var VersionedHostLocalStorageClearResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostLocalStorageReadError = lazy(() => indexedTaggedUnion({ V2: [1, HostLocalStorageReadError] }));
  var VersionedHostLocalStorageReadRequest = lazy(() => indexedTaggedUnion({ V2: [1, HostLocalStorageReadRequest] }));
  var VersionedHostLocalStorageReadResponse = lazy(() => indexedTaggedUnion({ V2: [1, HostLocalStorageReadResponse] }));
  var VersionedHostLocalStorageSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostLocalStorageSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostLocalStorageSubscribeRequest] }));
  var VersionedHostLocalStorageWriteError = lazy(() => indexedTaggedUnion({ V1: [0, V01HostLocalStorageReadError] }));
  var VersionedHostLocalStorageWriteRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostLocalStorageWriteRequest] }));
  var VersionedHostLocalStorageWriteResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostLocaleSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostLocaleSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, HostLocaleSubscribeItem] }));
  var VersionedHostLocaleSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostNavigateToError = lazy(() => indexedTaggedUnion({ V1: [0, HostNavigateToError] }));
  var VersionedHostNavigateToRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostNavigateToRequest] }));
  var VersionedHostNavigateToResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostPaymentBalanceSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentBalanceSubscribeError] }));
  var VersionedHostPaymentBalanceSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentBalanceSubscribeItem] }));
  var VersionedHostPaymentBalanceSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentBalanceSubscribeRequest] }));
  var VersionedHostPaymentError = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentError] }));
  var VersionedHostPaymentRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentRequest] }));
  var VersionedHostPaymentResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentResponse] }));
  var VersionedHostPaymentStatusSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentStatusSubscribeError] }));
  var VersionedHostPaymentStatusSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentStatusSubscribeItem] }));
  var VersionedHostPaymentStatusSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentStatusSubscribeRequest] }));
  var VersionedHostPaymentTopUpError = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentTopUpError] }));
  var VersionedHostPaymentTopUpRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostPaymentTopUpRequest] }));
  var VersionedHostPaymentTopUpResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var HostPlatform = lazy(() => Status("Web", "Android", "Ios", "Desktop", "Cli", "Unknown"));
  var VersionedHostPocketListSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostPocketListSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, HostPocketListSubscribeItem] }));
  var VersionedHostPocketListSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostPocketRemoveCardError = lazy(() => indexedTaggedUnion({ V1: [0, HostPocketRemoveCardError] }));
  var VersionedHostPocketRemoveCardRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostPocketRemoveCardRequest] }));
  var VersionedHostPocketRemoveCardResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostPushNotificationCancelError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostPushNotificationCancelRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostPushNotificationCancelRequest] }));
  var VersionedHostPushNotificationCancelResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostPushNotificationError = lazy(() => indexedTaggedUnion({ V1: [0, HostPushNotificationError] }));
  var VersionedHostPushNotificationRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostPushNotificationRequest] }));
  var VersionedHostPushNotificationResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostPushNotificationResponse] }));
  var VersionedHostRendererActionSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostRendererActionSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, HostRendererActionSubscribeItem] }));
  var VersionedHostRendererActionSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostRequestLoginError = lazy(() => indexedTaggedUnion({ V1: [0, HostRequestLoginError] }));
  var VersionedHostRequestLoginRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostRequestLoginRequest] }));
  var VersionedHostRequestLoginResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostRequestLoginResponse] }));
  var VersionedHostRequestResourceAllocationError = lazy(() => indexedTaggedUnion({ V1: [0, ResourceAllocationError] }));
  var VersionedHostRequestResourceAllocationRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostRequestResourceAllocationRequest] }));
  var VersionedHostRequestResourceAllocationResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostRequestResourceAllocationResponse] }));
  var HostSignPayloadData = lazy(() => Struct({ blockHash: Hex(), blockNumber: Hex(), era: Hex(), genesisHash: Hex(), method: Hex(), nonce: Hex(), specVersion: Hex(), tip: Hex(), transactionVersion: Hex(), signedExtensions: Vector(str), version: u32, assetId: Option(Hex()), metadataHash: Option(Hex()), mode: Option(u32), withSignedTransaction: OptionBool }));
  var VersionedHostSignPayloadError = lazy(() => indexedTaggedUnion({ V1: [0, HostSignPayloadError] }));
  var VersionedHostSignPayloadRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostSignPayloadRequest] }));
  var VersionedHostSignPayloadResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostSignPayloadResponse] }));
  var VersionedHostSignPayloadWithLegacyAccountError = lazy(() => indexedTaggedUnion({ V1: [0, HostSignPayloadError] }));
  var VersionedHostSignPayloadWithLegacyAccountRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostSignPayloadWithLegacyAccountRequest] }));
  var VersionedHostSignPayloadWithLegacyAccountResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostSignPayloadResponse] }));
  var VersionedHostSignRawError = lazy(() => indexedTaggedUnion({ V1: [0, HostSignPayloadError] }));
  var VersionedHostSignRawRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostSignRawRequest] }));
  var VersionedHostSignRawResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostSignPayloadResponse] }));
  var VersionedHostSignRawWithLegacyAccountError = lazy(() => indexedTaggedUnion({ V1: [0, HostSignPayloadError] }));
  var VersionedHostSignRawWithLegacyAccountRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostSignRawWithLegacyAccountRequest] }));
  var VersionedHostSignRawWithLegacyAccountResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostSignPayloadResponse] }));
  var VersionedHostThemeSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedHostThemeSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, HostThemeSubscribeItem] }));
  var VersionedHostThemeSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedHostWorkerBeginOperationError = lazy(() => indexedTaggedUnion({ V1: [0, HostWorkerOperationError] }));
  var VersionedHostWorkerBeginOperationRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostWorkerBeginOperationRequest] }));
  var VersionedHostWorkerBeginOperationResponse = lazy(() => indexedTaggedUnion({ V1: [0, HostWorkerBeginOperationResponse] }));
  var VersionedHostWorkerEndOperationError = lazy(() => indexedTaggedUnion({ V1: [0, HostWorkerOperationError] }));
  var VersionedHostWorkerEndOperationRequest = lazy(() => indexedTaggedUnion({ V1: [0, HostWorkerEndOperationRequest] }));
  var VersionedHostWorkerEndOperationResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var HostWorkerOperationError = lazy(() => TaggedUnion({ TooManyOpen: _void, Unknown: Struct({ reason: str }) }));
  var ImageFit = lazy(() => Status("None", "Fill", "Cover", "Contain", "ScaleDown"));
  var ImageProps = lazy(() => Struct({ source: ImageSource, fit: Option(ImageFit) }));
  var ImageSource = lazy(() => TaggedUnion({ Bulletin: str, Archive: str }));
  var LegacyAccount = lazy(() => Struct({ publicKey: Hex(), name: Option(str) }));
  var LegacyAccountTxPayload = lazy(() => Struct({ signer: AccountId, genesisHash: GenesisHash, callData: Hex(), extensions: Vector(TxPayloadExtension), txExtVersion: u8 }));
  var Modifier = lazy(() => TaggedUnion({ Margin: Dimensions, Padding: Dimensions, Background, Border: BorderStyle, Height: Size, Width: Size, MinWidth: Size, MinHeight: Size, FillWidth: bool, FillHeight: bool, Opacity: u8, BlendingMode }));
  var NotificationId = lazy(() => u32);
  var OperationId = lazy(() => u32);
  var OperationStartedResult = lazy(() => TaggedUnion({ Started: Struct({ operationId: str }), LimitReached: _void }));
  var PaymentTopUpSource = lazy(() => TaggedUnion({ ProductAccount: Struct({ derivationIndex: DerivationIndex }), PrivateKey: Struct({ sr25519SecretKey: Hex(64) }), Coins: Struct({ sr25519SecretKeys: Vector(Hex(64)) }) }));
  var PocketCard = lazy(() => Struct({ cardId: str, privileged: bool }));
  var PreimageSubmitError = lazy(() => TaggedUnion({ Unknown: Struct({ reason: str }) }));
  var ProductAccount = lazy(() => Struct({ publicKey: Hex() }));
  var ProductAccountId = lazy(() => Struct({ dotNsIdentifier: str, derivationIndex: DerivationIndex }));
  var ProductAccountTxPayload = lazy(() => Struct({ signer: ProductAccountId, genesisHash: GenesisHash, callData: Hex(), extensions: Vector(TxPayloadExtension), txExtVersion: u8 }));
  var ProductProofContext = lazy(() => Struct({ productId: str, suffix: DerivationIndex }));
  var VersionedProductRendererRenderError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedProductRendererRenderItem = lazy(() => indexedTaggedUnion({ V1: [0, RendererNode] }));
  var VersionedProductRendererRenderRequest = lazy(() => indexedTaggedUnion({ V1: [0, ProductRendererRenderRequest] }));
  var RawPayload = lazy(() => TaggedUnion({ Bytes: Struct({ bytes: Hex() }), Payload: Struct({ payload: str }) }));
  var RegisteredRingVrfKey = lazy(() => Struct({ handle: ProductAccountId, rings: Vector(RingLocation), publicKey: Option(RingVrfPublicKey) }));
  var VersionedRemoteChainHeadBodyError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainHeadBodyRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadBodyRequest] }));
  var VersionedRemoteChainHeadBodyResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadBodyResponse] }));
  var VersionedRemoteChainHeadCallError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainHeadCallRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadCallRequest] }));
  var VersionedRemoteChainHeadCallResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadCallResponse] }));
  var VersionedRemoteChainHeadContinueError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainHeadContinueRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadContinueRequest] }));
  var VersionedRemoteChainHeadContinueResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedRemoteChainHeadFollowError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainHeadFollowItem = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadFollowItem] }));
  var VersionedRemoteChainHeadFollowRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadFollowRequest] }));
  var VersionedRemoteChainHeadHeaderError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainHeadHeaderRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadHeaderRequest] }));
  var VersionedRemoteChainHeadHeaderResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadHeaderResponse] }));
  var VersionedRemoteChainHeadStopOperationError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainHeadStopOperationRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadStopOperationRequest] }));
  var VersionedRemoteChainHeadStopOperationResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedRemoteChainHeadStorageError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainHeadStorageRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadStorageRequest] }));
  var VersionedRemoteChainHeadStorageResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadStorageResponse] }));
  var VersionedRemoteChainHeadUnpinError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainHeadUnpinRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainHeadUnpinRequest] }));
  var VersionedRemoteChainHeadUnpinResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedRemoteChainInfoError = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainInfoError] }));
  var VersionedRemoteChainInfoRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainInfoRequest] }));
  var VersionedRemoteChainInfoResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainInfoResponse] }));
  var VersionedRemoteChainSpecChainNameError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainSpecChainNameRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainSpecChainNameRequest] }));
  var VersionedRemoteChainSpecChainNameResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainSpecChainNameResponse] }));
  var VersionedRemoteChainSpecGenesisHashError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainSpecGenesisHashRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainSpecGenesisHashRequest] }));
  var VersionedRemoteChainSpecGenesisHashResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainSpecGenesisHashResponse] }));
  var VersionedRemoteChainSpecPropertiesError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainSpecPropertiesRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainSpecPropertiesRequest] }));
  var VersionedRemoteChainSpecPropertiesResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainSpecPropertiesResponse] }));
  var VersionedRemoteChainTransactionBroadcastError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainTransactionBroadcastRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainTransactionBroadcastRequest] }));
  var VersionedRemoteChainTransactionBroadcastResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainTransactionBroadcastResponse] }));
  var VersionedRemoteChainTransactionStopError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteChainTransactionStopRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteChainTransactionStopRequest] }));
  var VersionedRemoteChainTransactionStopResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var RemotePermission = lazy(() => TaggedUnion({ Remote: Struct({ domains: Vector(str) }), WebRtc: _void, ChainSubmit: _void, PreimageSubmit: _void, StatementSubmit: _void }));
  var VersionedRemotePermissionError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemotePermissionRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemotePermissionRequest] }));
  var VersionedRemotePermissionResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemotePermissionResponse] }));
  var VersionedRemotePreimageLookupSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemotePreimageLookupSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, RemotePreimageLookupSubscribeItem] }));
  var VersionedRemotePreimageLookupSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemotePreimageLookupSubscribeRequest] }));
  var VersionedRemotePreimageSubmitError = lazy(() => indexedTaggedUnion({ V1: [0, PreimageSubmitError] }));
  var VersionedRemotePreimageSubmitRequest = lazy(() => indexedTaggedUnion({ V1: [0, Hex()] }));
  var VersionedRemotePreimageSubmitResponse = lazy(() => indexedTaggedUnion({ V1: [0, Hex()] }));
  var VersionedRemoteStatementStoreCreateProofAuthorizedError = lazy(() => indexedTaggedUnion({ V1: [0, RemoteStatementStoreCreateProofError] }));
  var VersionedRemoteStatementStoreCreateProofAuthorizedRequest = lazy(() => indexedTaggedUnion({ V1: [0, Statement] }));
  var VersionedRemoteStatementStoreCreateProofAuthorizedResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteStatementStoreCreateProofResponse] }));
  var VersionedRemoteStatementStoreCreateProofError = lazy(() => indexedTaggedUnion({ V1: [0, RemoteStatementStoreCreateProofError] }));
  var VersionedRemoteStatementStoreCreateProofRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteStatementStoreCreateProofRequest] }));
  var VersionedRemoteStatementStoreCreateProofResponse = lazy(() => indexedTaggedUnion({ V1: [0, RemoteStatementStoreCreateProofResponse] }));
  var VersionedRemoteStatementStoreSubmitError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteStatementStoreSubmitRequest = lazy(() => indexedTaggedUnion({ V1: [0, SignedStatement] }));
  var VersionedRemoteStatementStoreSubmitResponse = lazy(() => indexedTaggedUnion({ V1: [0, _void] }));
  var VersionedRemoteStatementStoreSubscribeError = lazy(() => indexedTaggedUnion({ V1: [0, GenericError] }));
  var VersionedRemoteStatementStoreSubscribeItem = lazy(() => indexedTaggedUnion({ V1: [0, RemoteStatementStoreSubscribeItem] }));
  var VersionedRemoteStatementStoreSubscribeRequest = lazy(() => indexedTaggedUnion({ V1: [0, RemoteStatementStoreSubscribeRequest] }));
  var RenderContext = lazy(() => TaggedUnion({ ChatMessage: Struct({ roomId: str, messageId: str, messageType: str }), InputWidget: Struct({ candidateId: str }), PocketCard: Struct({ cardId: str }) }));
  var RendererNode = lazy(() => TaggedUnion({ Nil: _void, String: Struct({ text: str }), Box: Struct({ modifiers: Vector(Modifier), props: BoxProps, children: Vector(RendererNode) }), Column: Struct({ modifiers: Vector(Modifier), props: ColumnProps, children: Vector(RendererNode) }), Row: Struct({ modifiers: Vector(Modifier), props: RowProps, children: Vector(RendererNode) }), Spacer: Struct({ modifiers: Vector(Modifier) }), Text: Struct({ modifiers: Vector(Modifier), props: TextProps, children: Vector(RendererNode) }), Button: Struct({ modifiers: Vector(Modifier), props: ButtonProps, children: Vector(RendererNode) }), TextField: Struct({ modifiers: Vector(Modifier), props: TextFieldProps }), Image: Struct({ modifiers: Vector(Modifier), props: ImageProps }), Effect: Struct({ props: EffectProps, children: Vector(RendererNode) }) }));
  var ResourceAllocationError = lazy(() => TaggedUnion({ Unknown: Struct({ reason: str }) }));
  var RingLocation = lazy(() => Struct({ chainId: GenesisHash, junctions: Vector(RingLocationJunction) }));
  var RingLocationJunction = lazy(() => TaggedUnion({ PalletInstance: u8, CollectionId: Hex() }));
  var RingVrfKeyDisclosure = lazy(() => Status("Anonymized", "PublicKey"));
  var RingVrfPublicKey = lazy(() => Hex(32));
  var RowProps = lazy(() => Struct({ verticalAlignment: Option(VerticalAlignment), horizontalArrangement: Option(Arrangement) }));
  var RuntimeApi = lazy(() => Struct({ name: str, version: u32 }));
  var RuntimeSpec = lazy(() => Struct({ specName: str, implName: str, specVersion: u32, implVersion: u32, transactionVersion: Option(u32), apis: Vector(RuntimeApi) }));
  var RuntimeType = lazy(() => TaggedUnion({ Valid: RuntimeSpec, Invalid: Struct({ error: str }) }));
  var Shape = lazy(() => TaggedUnion({ Rounded: Size, Circle: _void, Square: _void }));
  var SignedStatement = lazy(() => Struct({ proof: StatementProof, decryptionKey: Option(Hex(32)), expiry: Option(u64), channel: Option(Hex(32)), topics: Vector(Hex(32)), data: Option(Hex()) }));
  var Size = lazy(() => compact);
  var Statement = lazy(() => Struct({ proof: Option(StatementProof), decryptionKey: Option(Hex(32)), expiry: Option(u64), channel: Option(Hex(32)), topics: Vector(Hex(32)), data: Option(Hex()) }));
  var StatementProof = lazy(() => TaggedUnion({ Sr25519: Struct({ signature: Hex(64), signer: Hex(32) }), Ed25519: Struct({ signature: Hex(64), signer: Hex(32) }), Ecdsa: Struct({ signature: Hex(65), signer: Hex(33) }), OnChain: Struct({ who: Hex(32), blockHash: Hex(32), event: u64 }) }));
  var StorageQueryItem = lazy(() => Struct({ key: Hex(), queryType: StorageQueryType }));
  var StorageQueryType = lazy(() => Status("Value", "Hash", "ClosestDescendantMerkleValue", "DescendantsValues", "DescendantsHashes"));
  var StorageResultItem = lazy(() => Struct({ key: Hex(), value: Option(Hex()), hash: Option(Hex()), closestDescendantMerkleValue: Option(Hex()) }));
  var TextFieldProps = lazy(() => Struct({ text: str, placeholder: Option(str), label: Option(str), enabled: OptionBool, valueChangeAction: Option(str) }));
  var TextProps = lazy(() => Struct({ style: Option(TypographyStyle), color: Option(ColorToken) }));
  var ThemeName = lazy(() => TaggedUnion({ Custom: str, Default: _void }));
  var ThemeVariant = lazy(() => Status("Light", "Dark"));
  var Topic = lazy(() => Hex(32));
  var TxPayloadExtension = lazy(() => Struct({ id: str, extra: Hex(), additionalSigned: Hex() }));
  var TypographyStyle = lazy(() => Status("HeadlineLarge", "TitleMediumRegular", "BodyLargeRegular", "BodyMediumRegular", "BodySmallRegular"));
  var HostAccountConnectionStatusSubscribeItem = lazy(() => Status("Disconnected", "Connected"));
  var HostAccountCreateProofError = lazy(() => TaggedUnion({ RingNotFound: _void, NotMember: _void, KeyNotRegistered: _void, KeyNotInRing: _void, NotAllowlisted: _void, Rejected: _void, Unknown: Struct({ reason: str }) }));
  var HostAccountCreateProofRequest = lazy(() => Struct({ keyHandle: ProductAccountId, context: ProductProofContext, ringLocation: RingLocation, message: Hex() }));
  var HostAccountCreateProofResponse = lazy(() => Struct({ proof: Hex(), contextualAlias: ContextualAlias, ringIndex: u32, ringRevision: u32 }));
  var HostAccountGetAliasError = lazy(() => TaggedUnion({ RingNotFound: _void, NotMember: _void, KeyNotRegistered: _void, KeyNotInRing: _void, Rejected: _void, Unknown: Struct({ reason: str }) }));
  var HostAccountGetAliasRequest = lazy(() => Struct({ keyHandle: ProductAccountId, context: ProductProofContext, ringLocation: RingLocation }));
  var HostAccountGetError = lazy(() => TaggedUnion({ NotConnected: _void, Rejected: _void, DomainNotValid: _void, Unknown: Struct({ reason: str }) }));
  var HostAccountGetRequest = lazy(() => Struct({ productAccountId: ProductAccountId }));
  var HostAccountGetResponse = lazy(() => Struct({ account: ProductAccount }));
  var HostAccountListRingVrfKeysError = lazy(() => TaggedUnion({ NotConnected: _void, Rejected: _void, Unknown: Struct({ reason: str }) }));
  var HostAccountListRingVrfKeysRequest = lazy(() => Struct({ owner: str, disclosure: RingVrfKeyDisclosure }));
  var HostAccountRegisterRingVrfKeyError = lazy(() => TaggedUnion({ NotConnected: _void, RingNotFound: _void, Rejected: _void, Unknown: Struct({ reason: str }) }));
  var HostAccountRegisterRingVrfKeyRequest = lazy(() => Struct({ index: DerivationIndex, ring: RingLocation }));
  var HostAccountRingVrfSignError = lazy(() => TaggedUnion({ NotConnected: _void, KeyNotRegistered: _void, NotAllowlisted: _void, Rejected: _void, Unknown: Struct({ reason: str }) }));
  var HostAccountRingVrfSignRequest = lazy(() => Struct({ keyHandle: ProductAccountId, message: Hex() }));
  var HostAccountSignVrfError = lazy(() => TaggedUnion({ NotConnected: _void, Rejected: _void, Unknown: Struct({ reason: str }) }));
  var HostAccountSignVrfRequest = lazy(() => Struct({ account: ProductAccountId, transcriptLabel: Hex(), items: Vector(VrfTranscriptItem) }));
  var HostChatActionSubscribeItem = lazy(() => Struct({ roomId: str, peer: str, payload: ChatActionPayload }));
  var HostChatCreateRoomError = lazy(() => TaggedUnion({ PermissionDenied: _void, Unknown: Struct({ reason: str }) }));
  var HostChatCreateRoomRequest = lazy(() => Struct({ roomId: str, name: str, icon: str }));
  var HostChatCreateRoomResponse = lazy(() => Struct({ status: ChatRoomRegistrationStatus }));
  var HostChatListSubscribeItem = lazy(() => Struct({ rooms: Vector(ChatRoom) }));
  var HostChatPostMessageError = lazy(() => TaggedUnion({ MessageTooLarge: _void, Unknown: Struct({ reason: str }) }));
  var HostChatPostMessageRequest = lazy(() => Struct({ roomId: str, payload: ChatMessageContent }));
  var HostChatPostMessageResponse = lazy(() => Struct({ messageId: str }));
  var HostChatRegisterBotError = lazy(() => TaggedUnion({ PermissionDenied: _void, Unknown: Struct({ reason: str }) }));
  var HostChatRegisterBotRequest = lazy(() => Struct({ botId: str, name: str, icon: str }));
  var HostChatRegisterBotResponse = lazy(() => Struct({ status: ChatBotRegistrationStatus }));
  var HostCoinPaymentCreateChequeRequest = lazy(() => Struct({ from: CoinPaymentPurseId, to: CoinPaymentReceivable, amount: CoinPaymentBalance }));
  var HostCoinPaymentCreateChequeResponse = lazy(() => Struct({ cheque: CoinPaymentCheque }));
  var HostCoinPaymentCreatePurseRequest = lazy(() => Struct({ name: str }));
  var HostCoinPaymentCreatePurseResponse = lazy(() => Struct({ purse: CoinPaymentPurseId }));
  var HostCoinPaymentCreateReceivableRequest = lazy(() => Struct({ into: CoinPaymentPurseId }));
  var HostCoinPaymentCreateReceivableResponse = lazy(() => Struct({ receivable: CoinPaymentReceivable }));
  var HostCoinPaymentDeletePurseRequest = lazy(() => Struct({ target: CoinPaymentPurseId, drainInto: CoinPaymentPurseId }));
  var HostCoinPaymentDepositRequest = lazy(() => Struct({ cheque: CoinPaymentCheque }));
  var HostCoinPaymentListenForItem = lazy(() => TaggedUnion({ Channel: CoinPaymentTransmissionChannel, Cheque: CoinPaymentCheque }));
  var HostCoinPaymentListenForRequest = lazy(() => Struct({ receivable: CoinPaymentReceivable }));
  var HostCoinPaymentQueryPurseRequest = lazy(() => Struct({ purse: CoinPaymentPurseId }));
  var HostCoinPaymentQueryPurseResponse = lazy(() => Struct({ info: CoinPaymentPurseInfo }));
  var HostCoinPaymentRebalancePurseRequest = lazy(() => Struct({ from: CoinPaymentPurseId, to: CoinPaymentPurseId, amount: CoinPaymentBalance }));
  var HostCoinPaymentRefundRequest = lazy(() => Struct({ receivable: CoinPaymentReceivable }));
  var HostCreateTransactionError = lazy(() => TaggedUnion({ FailedToDecode: _void, Rejected: _void, NotSupported: Struct({ reason: str }), PermissionDenied: _void, Unknown: Struct({ reason: str }) }));
  var HostCreateTransactionResponse = lazy(() => Struct({ transaction: Hex() }));
  var HostCreateTransactionWithLegacyAccountResponse = lazy(() => Struct({ transaction: Hex() }));
  var HostDeriveEntropyError = lazy(() => TaggedUnion({ Unknown: Struct({ reason: str }) }));
  var HostDeriveEntropyRequest = lazy(() => Struct({ context: Hex() }));
  var HostDeriveEntropyResponse = lazy(() => Struct({ entropy: Hex(32) }));
  var HostDevicePermissionRequest = lazy(() => Status("Notifications", "Camera", "Microphone", "Bluetooth", "NFC", "Location", "Clipboard", "OpenUrl", "Biometrics"));
  var HostDevicePermissionResponse = lazy(() => Struct({ granted: bool }));
  var HostFeatureSupportedRequest = lazy(() => TaggedUnion({ Chain: Struct({ genesisHash: Hex() }) }));
  var HostFeatureSupportedResponse = lazy(() => Struct({ supported: bool }));
  var HostGetLegacyAccountsResponse = lazy(() => Struct({ accounts: Vector(LegacyAccount) }));
  var HostGetProductContextResponse = lazy(() => Struct({ productId: str }));
  var HostGetUserIdError = lazy(() => TaggedUnion({ PermissionDenied: _void, NotConnected: _void, Unknown: Struct({ reason: str }) }));
  var HostGetUserIdResponse = lazy(() => Struct({ primaryUsername: str }));
  var HostHandshakeError = lazy(() => TaggedUnion({ Timeout: _void, UnsupportedProtocolVersion: _void, Unknown: GenericError }));
  var HostHandshakeRequest = lazy(() => Struct({ codecVersion: u8 }));
  var HostLocalStorageChangeItem = lazy(() => Struct({ value: Option(Hex()) }));
  var HostLocalStorageClearRequest = lazy(() => Struct({ key: str }));
  var V01HostLocalStorageReadError = lazy(() => TaggedUnion({ Full: _void, Unknown: Struct({ reason: str }) }));
  var V01HostLocalStorageReadRequest = lazy(() => Struct({ key: str }));
  var HostLocalStorageReadResponse = lazy(() => Struct({ value: Option(Hex()) }));
  var HostLocalStorageSubscribeRequest = lazy(() => Struct({ key: str }));
  var HostLocalStorageWriteRequest = lazy(() => Struct({ key: str, value: Hex() }));
  var HostLocaleSubscribeItem = lazy(() => Struct({ languageTag: str }));
  var HostNavigateToError = lazy(() => TaggedUnion({ PermissionDenied: _void, Unknown: Struct({ reason: str }) }));
  var HostNavigateToRequest = lazy(() => Struct({ url: str }));
  var HostPaymentBalanceSubscribeError = lazy(() => TaggedUnion({ PermissionDenied: _void, Unknown: Struct({ reason: str }) }));
  var HostPaymentBalanceSubscribeItem = lazy(() => Struct({ available: Balance }));
  var HostPaymentBalanceSubscribeRequest = lazy(() => Struct({ purse: Option(CoinPaymentPurseId) }));
  var HostPaymentError = lazy(() => TaggedUnion({ Rejected: _void, InsufficientBalance: _void, Unknown: Struct({ reason: str }) }));
  var HostPaymentRequest = lazy(() => Struct({ from: Option(CoinPaymentPurseId), amount: Balance, destination: Hex(32) }));
  var HostPaymentResponse = lazy(() => Struct({ id: str }));
  var HostPaymentStatusSubscribeError = lazy(() => TaggedUnion({ PaymentNotFound: _void, Unknown: Struct({ reason: str }) }));
  var HostPaymentStatusSubscribeItem = lazy(() => TaggedUnion({ Processing: _void, Completed: _void, Failed: Struct({ reason: str }) }));
  var HostPaymentStatusSubscribeRequest = lazy(() => Struct({ paymentId: str }));
  var HostPaymentTopUpError = lazy(() => TaggedUnion({ InsufficientFunds: _void, InvalidSource: _void, PartialPayment: Struct({ credited: Balance }), Unknown: Struct({ reason: str }) }));
  var HostPaymentTopUpRequest = lazy(() => Struct({ into: Option(CoinPaymentPurseId), amount: Balance, source: PaymentTopUpSource }));
  var HostPocketListSubscribeItem = lazy(() => Struct({ cards: Vector(PocketCard) }));
  var HostPocketRemoveCardError = lazy(() => TaggedUnion({ Privileged: _void, Unknown: Struct({ reason: str }) }));
  var HostPocketRemoveCardRequest = lazy(() => Struct({ cardId: str }));
  var HostPushNotificationCancelRequest = lazy(() => Struct({ id: NotificationId }));
  var HostPushNotificationError = lazy(() => TaggedUnion({ ScheduleLimitReached: _void, Unknown: Struct({ reason: str }) }));
  var HostPushNotificationRequest = lazy(() => Struct({ text: str, deeplink: Option(str), scheduledAt: Option(u64) }));
  var HostPushNotificationResponse = lazy(() => Struct({ id: NotificationId }));
  var HostRendererActionSubscribeItem = lazy(() => Struct({ context: RenderContext, actionId: str, payload: Hex() }));
  var HostRequestLoginError = lazy(() => TaggedUnion({ Unknown: Struct({ reason: str }) }));
  var HostRequestLoginRequest = lazy(() => Struct({ reason: Option(str) }));
  var HostRequestLoginResponse = lazy(() => Status("Success", "AlreadyConnected", "Rejected"));
  var HostRequestResourceAllocationRequest = lazy(() => Struct({ resources: Vector(AllocatableResource) }));
  var HostRequestResourceAllocationResponse = lazy(() => Struct({ outcomes: Vector(AllocationOutcome) }));
  var HostSignPayloadError = lazy(() => TaggedUnion({ FailedToDecode: _void, Rejected: _void, PermissionDenied: _void, Unknown: Struct({ reason: str }) }));
  var HostSignPayloadRequest = lazy(() => Struct({ account: ProductAccountId, payload: HostSignPayloadData }));
  var HostSignPayloadResponse = lazy(() => Struct({ signature: Hex(), signedTransaction: Option(Hex()) }));
  var HostSignPayloadWithLegacyAccountRequest = lazy(() => Struct({ signer: str, payload: HostSignPayloadData }));
  var HostSignRawRequest = lazy(() => Struct({ account: ProductAccountId, payload: RawPayload }));
  var HostSignRawWithLegacyAccountRequest = lazy(() => Struct({ signer: str, payload: RawPayload }));
  var HostThemeSubscribeItem = lazy(() => Struct({ name: ThemeName, variant: ThemeVariant }));
  var HostWorkerBeginOperationRequest = lazy(() => Struct({ label: Option(str) }));
  var HostWorkerBeginOperationResponse = lazy(() => Struct({ id: OperationId }));
  var HostWorkerEndOperationRequest = lazy(() => Struct({ id: OperationId }));
  var ProductRendererRenderRequest = lazy(() => Struct({ context: RenderContext, payload: Hex() }));
  var RemoteChainHeadBodyRequest = lazy(() => Struct({ genesisHash: Hex(), followSubscriptionId: str, hash: Hex() }));
  var RemoteChainHeadBodyResponse = lazy(() => Struct({ operation: OperationStartedResult }));
  var RemoteChainHeadCallRequest = lazy(() => Struct({ genesisHash: Hex(), followSubscriptionId: str, hash: Hex(), function: str, callParameters: Hex() }));
  var RemoteChainHeadCallResponse = lazy(() => Struct({ operation: OperationStartedResult }));
  var RemoteChainHeadContinueRequest = lazy(() => Struct({ genesisHash: Hex(), followSubscriptionId: str, operationId: str }));
  var RemoteChainHeadFollowItem = lazy(() => TaggedUnion({ Initialized: Struct({ finalizedBlockHashes: Vector(Hex()), finalizedBlockRuntime: Option(RuntimeType) }), NewBlock: Struct({ blockHash: Hex(), parentBlockHash: Hex(), newRuntime: Option(RuntimeType) }), BestBlockChanged: Struct({ bestBlockHash: Hex() }), Finalized: Struct({ finalizedBlockHashes: Vector(Hex()), prunedBlockHashes: Vector(Hex()) }), OperationBodyDone: Struct({ operationId: str, value: Vector(Hex()) }), OperationCallDone: Struct({ operationId: str, output: Hex() }), OperationStorageItems: Struct({ operationId: str, items: Vector(StorageResultItem) }), OperationStorageDone: Struct({ operationId: str }), OperationWaitingForContinue: Struct({ operationId: str }), OperationInaccessible: Struct({ operationId: str }), OperationError: Struct({ operationId: str, error: str }), Stop: _void }));
  var RemoteChainHeadFollowRequest = lazy(() => Struct({ genesisHash: Hex(), withRuntime: bool }));
  var RemoteChainHeadHeaderRequest = lazy(() => Struct({ genesisHash: Hex(), followSubscriptionId: str, hash: Hex() }));
  var RemoteChainHeadHeaderResponse = lazy(() => Struct({ header: Option(Hex()) }));
  var RemoteChainHeadStopOperationRequest = lazy(() => Struct({ genesisHash: Hex(), followSubscriptionId: str, operationId: str }));
  var RemoteChainHeadStorageRequest = lazy(() => Struct({ genesisHash: Hex(), followSubscriptionId: str, hash: Hex(), items: Vector(StorageQueryItem), childTrie: Option(Hex()) }));
  var RemoteChainHeadStorageResponse = lazy(() => Struct({ operation: OperationStartedResult }));
  var RemoteChainHeadUnpinRequest = lazy(() => Struct({ genesisHash: Hex(), followSubscriptionId: str, hashes: Vector(Hex()) }));
  var RemoteChainInfoError = lazy(() => TaggedUnion({ NotSupported: _void, Unknown: GenericError }));
  var RemoteChainInfoRequest = lazy(() => Struct({ chain: ChainIdentifier }));
  var RemoteChainInfoResponse = lazy(() => Struct({ network: str, chain: ChainIdentifier, genesisHash: Hex(32) }));
  var RemoteChainSpecChainNameRequest = lazy(() => Struct({ genesisHash: Hex() }));
  var RemoteChainSpecChainNameResponse = lazy(() => Struct({ chainName: str }));
  var RemoteChainSpecGenesisHashRequest = lazy(() => Struct({ genesisHash: Hex() }));
  var RemoteChainSpecGenesisHashResponse = lazy(() => Struct({ genesisHash: Hex() }));
  var RemoteChainSpecPropertiesRequest = lazy(() => Struct({ genesisHash: Hex() }));
  var RemoteChainSpecPropertiesResponse = lazy(() => Struct({ properties: str }));
  var RemoteChainTransactionBroadcastRequest = lazy(() => Struct({ genesisHash: Hex(), transaction: Hex() }));
  var RemoteChainTransactionBroadcastResponse = lazy(() => Struct({ operationId: Option(str) }));
  var RemoteChainTransactionStopRequest = lazy(() => Struct({ genesisHash: Hex(), operationId: str }));
  var RemotePermissionRequest = lazy(() => Struct({ permission: RemotePermission }));
  var RemotePermissionResponse = lazy(() => Struct({ granted: bool }));
  var RemotePreimageLookupSubscribeItem = lazy(() => Struct({ value: Option(Hex()) }));
  var RemotePreimageLookupSubscribeRequest = lazy(() => Struct({ key: Hex() }));
  var RemoteStatementStoreCreateProofError = lazy(() => TaggedUnion({ UnableToSign: _void, UnknownAccount: _void, Unknown: Struct({ reason: str }) }));
  var RemoteStatementStoreCreateProofRequest = lazy(() => Struct({ productAccountId: ProductAccountId, statement: Statement }));
  var RemoteStatementStoreCreateProofResponse = lazy(() => Struct({ proof: StatementProof }));
  var RemoteStatementStoreSubscribeItem = lazy(() => Struct({ statements: Vector(SignedStatement), isComplete: bool }));
  var RemoteStatementStoreSubscribeRequest = lazy(() => TaggedUnion({ MatchAll: Vector(Topic), MatchAny: Vector(Topic) }));
  var HostLocalStorageReadError = lazy(() => TaggedUnion({ Full: _void, AccessNotGranted: _void, Unknown: Struct({ reason: str }) }));
  var HostLocalStorageReadRequest = lazy(() => Struct({ product: Option(str), key: str }));
  var VerticalAlignment = lazy(() => Status("Top", "Center", "Bottom"));
  var VrfSignature = lazy(() => Struct({ preOutput: Hex(32), proof: Hex(64) }));
  var VrfTranscriptItem = lazy(() => Struct({ label: Hex(), value: Hex() }));

  // ../packages/truapi/dist/generated/wire-table.js
  var PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION = {
    trait: 10,
    method: 2,
    kind: "request"
  };
  var PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION = {
    trait: 10,
    method: 3,
    kind: "request"
  };

  // src/network-transport.ts
  function createPermissionAuthorization(win) {
    const bootstrap = win;
    const port = bootstrap.__truapi_network_port__;
    freezeAndDelete(win, "__truapi_network_port__");
    const endpoint = bootstrap.__truapi_localhost?.url;
    const apply = Reflect.apply;
    const descriptor = Object.getOwnPropertyDescriptor;
    const hasOwn = Object.prototype.hasOwnProperty;
    const NativeBytes = win.Uint8Array;
    const bytesPrototype = Object.getPrototypeOf(NativeBytes.prototype);
    const bytesLength = descriptor(bytesPrototype, "length").get;
    const bytesBuffer = descriptor(bytesPrototype, "buffer").get;
    const bytesOffset = descriptor(bytesPrototype, "byteOffset").get;
    const bufferLength = descriptor(
      win.ArrayBuffer.prototype,
      "byteLength"
    ).get;
    const messageData = descriptor(win.MessageEvent.prototype, "data").get;
    const encoder = new win.TextEncoder();
    const encode = win.TextEncoder.prototype.encode;
    const schedule = win.setTimeout.bind(win);
    const cancel = win.clearTimeout.bind(win);
    const NativeURL = win.URL;
    const hostname = descriptor(NativeURL.prototype, "hostname").get;
    const protocol = descriptor(NativeURL.prototype, "protocol").get;
    const indexOf = String.prototype.indexOf;
    const requestId = "0000000000000000";
    const idLength = scale_exports.str.enc(requestId).length;
    const idOffset = idLength - requestId.length;
    function template(ids, messageType, value) {
      return encodeWireMessage({
        requestId,
        payload: {
          traitId: ids.trait,
          methodId: ids.method,
          messageType,
          value
        }
      })._unsafeUnwrap();
    }
    const requestTemplate = template(
      PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION,
      MESSAGE_TYPE_REQUEST,
      VersionedRemotePermissionRequest.enc({
        tag: "V1",
        value: { permission: { tag: "Remote", value: { domains: [""] } } }
      })
    );
    const requestPrefixLength = requestTemplate.length - scale_exports.str.enc("").length;
    const responseTemplate = template(
      PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION,
      MESSAGE_TYPE_RESPONSE,
      scale_exports.Result(
        VersionedRemotePermissionResponse,
        scale_exports.CallError(VersionedRemotePermissionError)
      ).enc({ success: true, value: { tag: "V1", value: { granted: true } } })
    );
    const webRtcRequest = template(
      PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION,
      MESSAGE_TYPE_REQUEST,
      VersionedRemotePermissionRequest.enc({
        tag: "V1",
        value: { permission: { tag: "WebRtc" } }
      })
    );
    const cameraRequest = template(
      PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION,
      MESSAGE_TYPE_REQUEST,
      VersionedHostDevicePermissionRequest.enc({ tag: "V1", value: "Camera" })
    );
    const microphoneRequest = template(
      PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION,
      MESSAGE_TYPE_REQUEST,
      VersionedHostDevicePermissionRequest.enc({ tag: "V1", value: "Microphone" })
    );
    const deviceResponse = template(
      PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION,
      MESSAGE_TYPE_RESPONSE,
      scale_exports.Result(
        VersionedHostDevicePermissionResponse,
        scale_exports.CallError(VersionedHostDevicePermissionError)
      ).enc({ success: true, value: { tag: "V1", value: { granted: true } } })
    );
    let pending;
    let tail;
    let counter = 0;
    let open = false;
    let closed = false;
    let send;
    let close;
    function remove(request) {
      let previous;
      for (let entry = pending; entry; entry = entry.next) {
        if (entry === request) {
          if (previous) previous.next = entry.next;
          else pending = entry.next;
          if (tail === entry) tail = previous;
          cancel(entry.deadline);
          return true;
        }
        previous = entry;
      }
      return false;
    }
    function disconnect() {
      if (closed) return;
      closed = true;
      while (pending) {
        const entry = pending;
        remove(entry);
        entry.decide(false);
      }
      try {
        close?.();
      } catch {
      }
    }
    function receive(event) {
      try {
        let data;
        try {
          data = apply(messageData, event, []);
        } catch {
          const field = descriptor(event, "data");
          if (field && apply(hasOwn, field, ["value"])) data = field.value;
        }
        let bytes;
        try {
          const length2 = apply(bufferLength, data, []);
          bytes = new NativeBytes(data, 0, length2);
        } catch {
          bytes = new NativeBytes(
            apply(bytesBuffer, data, []),
            apply(bytesOffset, data, []),
            apply(bytesLength, data, [])
          );
        }
        const length = apply(bytesLength, bytes, []);
        for (let entry = pending; entry; entry = entry.next) {
          let matches = length >= idLength;
          for (let index = 0; matches && index < idLength; index++) {
            matches = bytes[index] === entry.expected[index];
          }
          if (!matches) continue;
          let allowed = length === apply(bytesLength, entry.expected, []);
          for (let index = idLength; allowed && index < length; index++) {
            allowed = bytes[index] === entry.expected[index];
          }
          remove(entry);
          entry.decide(allowed);
          return;
        }
      } catch {
        disconnect();
      }
    }
    try {
      if (port) {
        const postMessage = port.postMessage;
        const closePort = port.close;
        send = (frame) => apply(postMessage, port, [frame]);
        close = () => {
          if (closePort) apply(closePort, port, []);
        };
        port.onmessage = receive;
        port.onmessageerror = disconnect;
        port.start?.();
        open = true;
      } else if (typeof endpoint === "string") {
        const socket = new win.WebSocket(endpoint);
        const socketSend = win.WebSocket.prototype.send;
        const socketClose = win.WebSocket.prototype.close;
        const listen = win.EventTarget.prototype.addEventListener;
        socket.binaryType = "arraybuffer";
        send = (frame) => apply(socketSend, socket, [frame]);
        close = () => apply(socketClose, socket, []);
        apply(listen, socket, ["message", receive]);
        apply(listen, socket, ["error", disconnect]);
        apply(listen, socket, ["close", disconnect]);
        apply(listen, socket, [
          "open",
          () => {
            open = true;
            try {
              for (let entry = pending; entry; entry = entry.next)
                send(entry.frame);
            } catch {
              disconnect();
            }
          }
        ]);
      } else {
        closed = true;
      }
    } catch {
      disconnect();
    }
    function authorize(template2, response, domain, decide) {
      if (closed || !send) {
        decide(false);
        return () => {
        };
      }
      try {
        const encodedDomain = domain === null ? new NativeBytes(0) : apply(encode, encoder, [domain]);
        const length = apply(bytesLength, encodedDomain, []);
        if (length >= 2 ** 30) {
          decide(false);
          return () => {
          };
        }
        const width = domain === null ? 0 : length < 64 ? 1 : length < 16384 ? 2 : 4;
        let compactLength = length * 4 + (width === 1 ? 0 : width === 2 ? 1 : 2);
        const prefixLength = domain === null ? apply(bytesLength, template2, []) : requestPrefixLength;
        const responseLength = apply(bytesLength, response, []);
        const frame = new NativeBytes(prefixLength + width + length);
        const expected = new NativeBytes(responseLength);
        for (let index = 0; index < prefixLength; index++)
          frame[index] = template2[index];
        for (let index = 0; index < responseLength; index++)
          expected[index] = response[index];
        let sequence = ++counter;
        for (let index = idLength - 1; index >= idOffset; index--) {
          const digit = sequence % 16;
          sequence = (sequence - digit) / 16;
          frame[index] = expected[index] = digit < 10 ? 48 + digit : 87 + digit;
        }
        for (let index = 0; index < width; index++) {
          frame[prefixLength + index] = compactLength & 255;
          compactLength >>>= 8;
        }
        for (let index = 0; index < length; index++)
          frame[prefixLength + width + index] = encodedDomain[index];
        const entry = {
          expected,
          frame,
          decide,
          next: void 0,
          deadline: schedule(() => {
            if (remove(entry)) decide(false);
          }, 12e4)
        };
        if (tail) tail.next = entry;
        else pending = entry;
        tail = entry;
        if (open) send(frame);
        return () => {
          remove(entry);
        };
      } catch {
        disconnect();
        decide(false);
        return () => {
        };
      }
    }
    function authorizeNetwork(url, decide) {
      let domain;
      try {
        const destination = new NativeURL(url);
        const scheme = apply(protocol, destination, []);
        domain = apply(hostname, destination, []);
        if (scheme !== "http:" && scheme !== "https:" && scheme !== "ws:" && scheme !== "wss:" || !domain || apply(indexOf, domain, ["*"]) !== -1) {
          decide(false);
          return () => {
          };
        }
      } catch {
        decide(false);
        return () => {
        };
      }
      return authorize(requestTemplate, responseTemplate, domain, decide);
    }
    function authorizeMedia(audio, video, decide) {
      let pending2;
      function request(template2, microphoneNext) {
        const entry = { cancel: void 0 };
        pending2 = entry;
        const cancel2 = authorize(template2, deviceResponse, null, (allowed) => {
          if (pending2 !== entry) return;
          pending2 = void 0;
          if (allowed && microphoneNext) request(microphoneRequest, false);
          else decide(allowed);
        });
        if (pending2 === entry) entry.cancel = cancel2;
        else cancel2();
      }
      if (video) request(cameraRequest, audio);
      else if (audio) request(microphoneRequest, false);
      else decide(false);
      return () => {
        const cancel2 = pending2?.cancel;
        pending2 = void 0;
        cancel2?.();
      };
    }
    return {
      network: authorizeNetwork,
      webRtc: closed ? false : (decide) => authorize(webRtcRequest, responseTemplate, null, decide),
      media: closed ? false : authorizeMedia
    };
  }

  // src/index.ts
  installContainer(createPermissionAuthorization(window));
})();
