import { expect, spyOn, test } from "bun:test";
import { chromium } from "playwright-core";
import {
  decodeWireMessage,
  encodeWireMessage,
  MESSAGE_TYPE_REQUEST,
  MESSAGE_TYPE_RESPONSE,
  scale,
  VersionedRemotePermissionRequest,
  VersionedRemotePermissionResponse,
  VersionedRemotePermissionError,
  type ProtocolMessage,
  type WireProvider,
} from "@parity/truapi";
import { PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION } from "../../../../js/packages/truapi/src/generated/wire-table.ts";
import { runBrowserScript } from "./sandbox-runner.ts";

const provider = {
  postMessage() {},
  subscribe() {
    return () => {};
  },
  dispose() {},
} satisfies WireProvider;

function reply(request: ProtocolMessage, allowed: boolean): Uint8Array {
  const value = scale
    .Result(
      VersionedRemotePermissionResponse,
      scale.CallError(VersionedRemotePermissionError),
    )
    .enc({
      success: true,
      value: { tag: "V1", value: { granted: allowed } },
    });
  return encodeWireMessage({
    ...request,
    payload: { ...request.payload, messageType: MESSAGE_TYPE_RESPONSE, value },
  })._unsafeUnwrap();
}

function requestScript(api: "fetch" | "XHR"): string {
  if (api === "fetch") return "const request = fetch;";
  return `
    function request(url, options = {}) {
      return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        XMLHttpRequest.prototype.open.call(xhr, options.method ?? 'GET', url);
        xhr.onload = () => resolve({ text: async () => xhr.responseText });
        xhr.onerror = () => reject(new TypeError('XHR failed'));
        xhr.onabort = () => reject(options.signal?.reason ?? new DOMException('Aborted', 'AbortError'));
        for (const [name, value] of Object.entries(options.headers ?? {})) xhr.setRequestHeader(name, value);
        options.signal?.addEventListener('abort', () => xhr.abort(), { once: true });
        XMLHttpRequest.prototype.send.call(xhr, options.body ?? null);
      });
    }
  `;
}

test("runs a product with CLI helpers but no host runtime capabilities", async () => {
  const messages: string[] = [];
  await runBrowserScript({
    source: `
      assert(host.productId === 'sandbox.testnet');
      assert(host.productAccount(2).derivationIndex.value === 2);
      assert(typeof truapi.permissions.requestRemotePermission === 'function');
      for (const name of ['process', 'Bun', 'require', 'Worker', 'SharedWorker', 'WebTransport', 'RTCPeerConnection']) {
        assert(typeof globalThis[name] === 'undefined', name + ' must be unavailable');
      }
      for (const evaluate of [() => eval('1'), () => new Function('return 1')()]) {
        try { evaluate(); throw new Error('dynamic code execution was allowed'); }
        catch (error) { assert(error instanceof EvalError); }
      }
      assert((await WebAssembly.compile(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0]))) instanceof WebAssembly.Module);
      document.body.innerHTML = '<iframe></iframe>';
      const child = document.querySelector('iframe').contentWindow;
      for (const name of ['Worker', 'SharedWorker', 'RTCPeerConnection']) {
        assert(typeof child[name] === 'undefined', name + ' must be unavailable in blank frames');
      }
      export default async (context) => console.log('completed ' + context.productId);
    `,
    productId: "sandbox.testnet",
    provider,
    authorize: async () => false,
    onConsole: (_, message) => messages.push(message),
    timeoutMs: 10_000,
  });
  expect(messages).toContain("completed sandbox.testnet");
}, 20_000);

test("denied fetch, XHR and image requests never reach the server", async () => {
  const hits: string[] = [];
  const authorizations: string[] = [];
  const endpoint = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request) {
      hits.push(new URL(request.url).pathname);
      return new Response("unexpected", {
        headers: { "Access-Control-Allow-Origin": "*" },
      });
    },
  });
  try {
    await runBrowserScript({
      source: `
        ${requestScript("XHR")}
        const endpoint = ${JSON.stringify(endpoint.url.href)};
        try { await fetch(endpoint + 'fetch'); throw new Error('unexpected success'); }
        catch (error) { assert(error instanceof TypeError); }
        try { await request(endpoint + 'xhr'); throw new Error('unexpected XHR success'); }
        catch (error) { assert(error instanceof TypeError); }
        await new Promise((resolve, reject) => {
          const image = new Image(); image.onerror = resolve; image.onload = () => reject(new Error('image escaped'));
          image.src = endpoint + 'image';
        });
      `,
      productId: "sandbox.testnet",
      provider,
      authorize: async (url) => {
        authorizations.push(new URL(url).pathname);
        return false;
      },
      timeoutMs: 10_000,
    });
    expect({ hits, authorizations }).toEqual({
      hits: [],
      authorizations: ["/fetch", "/xhr"],
    });
  } finally {
    endpoint.stop(true);
  }
}, 20_000);

for (const api of ["fetch", "XHR"] as const) {
  test(`revocation blocks the next ${api} after an authorized response`, async () => {
    const hits: string[] = [];
    let allowed = true;
    let authorizations = 0;
    const endpoint = Bun.serve({
      hostname: "127.0.0.1",
      port: 0,
      fetch(request) {
        hits.push(new URL(request.url).pathname);
        allowed = false;
        return new Response("authorized", {
          headers: { "Access-Control-Allow-Origin": "*" },
        });
      },
    });
    try {
      await runBrowserScript({
        source: `
        ${requestScript(api)}
        const endpoint = ${JSON.stringify(endpoint.url.href)};
        assert(await (await request(endpoint + 'allowed')).text() === 'authorized');
        try { await request(endpoint + 'revoked'); throw new Error('unexpected success'); }
        catch (error) { assert(error instanceof TypeError); }
      `,
        productId: "sandbox.testnet",
        provider,
        authorize: async () => {
          authorizations++;
          return allowed;
        },
        timeoutMs: 10_000,
      });
      expect(hits).toEqual(["/allowed"]);
      expect(authorizations).toBe(2);
    } finally {
      endpoint.stop(true);
    }
  }, 20_000);
}

test("cross-host redirects use the initial request's authorization", async () => {
  const hits: string[] = [];
  const authorizations: string[] = [];
  const target = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch() {
      hits.push("destination");
      return new Response("authorized", {
        headers: { "Access-Control-Allow-Origin": "*" },
      });
    },
  });
  const destination = new URL(target.url);
  destination.hostname = "localhost";
  const redirect = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch() {
      hits.push("allowed");
      return new Response(null, {
        status: 302,
        headers: {
          Location: destination.href,
          "Access-Control-Allow-Origin": "*",
        },
      });
    },
  });
  try {
    for (const api of ["fetch", "XHR"] as const) {
      for (const allowRequest of [false, true]) {
        hits.length = 0;
        authorizations.length = 0;
        await runBrowserScript({
          source: `
            ${requestScript(api)}
            const endpoint = ${JSON.stringify(redirect.url.href)};
            if (${allowRequest}) {
              assert(await (await request(endpoint)).text() === 'authorized');
            } else {
              try { await request(endpoint); throw new Error('denied request was sent'); }
              catch (error) { assert(error instanceof TypeError); }
            }
          `,
          productId: "sandbox.testnet",
          provider,
          authorize: async (url) => {
            authorizations.push(url);
            return allowRequest && url === redirect.url.href;
          },
          timeoutMs: 10_000,
        });
        expect({ hits, authorizations }).toEqual({
          hits: allowRequest ? ["allowed", "destination"] : [],
          authorizations: [redirect.url.href],
        });
      }
    }
  } finally {
    redirect.stop(true);
    target.stop(true);
  }
}, 20_000);

test("XHR preserves request headers and body and native binary response metadata", async () => {
  const hits: { method: string; header: string | null; body: number[] }[] = [];
  const authorizations: string[] = [];
  const endpoint = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    async fetch(request) {
      hits.push({
        method: request.method,
        header: request.headers.get("x-product"),
        body: Array.from(new Uint8Array(await request.arrayBuffer())),
      });
      return new Response(
        request.method === "OPTIONS" ? null : new Uint8Array([0, 255, 42]),
        {
          status: request.method === "OPTIONS" ? 200 : 201,
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST",
            "Access-Control-Allow-Headers": "x-product",
            "Access-Control-Expose-Headers": "x-reply",
            "x-reply": "preserved",
          },
        },
      );
    },
  });
  try {
    await runBrowserScript({
      source: `
        const xhr = new XMLHttpRequest();
        xhr.open('POST', ${JSON.stringify(endpoint.url.href)});
        assert(xhr.readyState === XMLHttpRequest.OPENED);
        xhr.responseType = 'arraybuffer';
        xhr.setRequestHeader('x-product', 'present');
        const completed = new Promise((resolve, reject) => {
          xhr.onload = resolve;
          xhr.onerror = () => reject(new Error('XHR failed'));
        });
        xhr.send(new Uint8Array([0, 255, 42]));
        await completed;
        assert(xhr.readyState === XMLHttpRequest.DONE);
        assert(xhr.status === 201);
        assert(xhr.responseURL === ${JSON.stringify(endpoint.url.href)});
        assert(xhr.getResponseHeader('x-reply') === 'preserved');
        assert(xhr.response instanceof ArrayBuffer);
        assert(JSON.stringify(Array.from(new Uint8Array(xhr.response))) === '[0,255,42]');
      `,
      productId: "sandbox.testnet",
      provider,
      authorize: async (url) => {
        authorizations.push(url);
        return true;
      },
      timeoutMs: 10_000,
    });
    expect({ hits, authorizations }).toEqual({
      hits: [
        { method: "OPTIONS", header: null, body: [] },
        { method: "POST", header: "present", body: [0, 255, 42] },
      ],
      authorizations: [endpoint.url.href],
    });
  } finally {
    endpoint.stop(true);
  }
}, 20_000);

test("script rejection is reported even if browser cleanup fails", async () => {
  const launch = chromium.launch.bind(chromium);
  const mocked = spyOn(chromium, "launch").mockImplementation(
    async (options) => {
      const browser = await launch(options);
      const close = browser.close.bind(browser);
      browser.close = async () => {
        await close();
        throw new Error("browser cleanup failed");
      };
      return browser;
    },
  );
  try {
    await expect(
      runBrowserScript({
        source: "throw new Error('product failure');",
        productId: "sandbox.testnet",
        provider,
        authorize: async () => false,
        timeoutMs: 10_000,
      }),
    ).rejects.toThrow("product failure");
  } finally {
    mocked.mockRestore();
  }
}, 20_000);

test("a stalled product reports a timeout", async () => {
  await expect(
    runBrowserScript({
      source: "await new Promise(() => {});",
      productId: "sandbox.testnet",
      provider,
      authorize: async () => false,
      timeoutMs: 250,
    }),
  ).rejects.toThrow("Product script timed out");
}, 20_000);

test("authorization errors fail closed before any request reaches the server", async () => {
  const hits: string[] = [];
  const endpoint = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request) {
      hits.push(request.url);
      return new Response("unexpected");
    },
  });
  try {
    await runBrowserScript({
      source: `
          try { await fetch(${JSON.stringify(endpoint.url.href)}); throw new Error('unexpected success'); }
          catch (error) { assert(error instanceof TypeError); }
        `,
      productId: "sandbox.testnet",
      provider,
      authorize: async () => {
        throw new Error("Permission service unavailable");
      },
      timeoutMs: 10_000,
    });
    expect(hits).toEqual([]);
  } finally {
    endpoint.stop(true);
  }
}, 20_000);

for (const api of ["fetch", "XHR"] as const) {
  test(`one ${api} authorization covers a POST redirect and both CORS preflights`, async () => {
    const hits: string[] = [];
    const authorizations: string[] = [];
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST",
      "Access-Control-Allow-Headers": "x-product",
    };
    const target = Bun.serve({
      hostname: "127.0.0.1",
      port: 0,
      async fetch(request) {
        hits.push(`target ${request.method} ${await request.text()}`);
        return new Response(request.method === "OPTIONS" ? null : "received", {
          headers: cors,
        });
      },
    });
    const redirect = Bun.serve({
      hostname: "127.0.0.1",
      port: 0,
      async fetch(request) {
        hits.push(`redirect ${request.method} ${await request.text()}`);
        return new Response(null, {
          status: request.method === "OPTIONS" ? 200 : 307,
          headers: { ...cors, Location: target.url.href },
        });
      },
    });
    try {
      await runBrowserScript({
        source: `
        ${requestScript(api)}
        const response = await request(${JSON.stringify(redirect.url.href)}, {
          method: 'POST', headers: { 'x-product': 'present' }, body: 'preserved body',
        });
        assert(await response.text() === 'received');
      `,
        productId: "sandbox.testnet",
        provider,
        authorize: async (url) => {
          authorizations.push(url);
          return authorizations.length === 1;
        },
        timeoutMs: 10_000,
      });
      expect({ hits, authorizations }).toEqual({
        hits: [
          "redirect OPTIONS ",
          "redirect POST preserved body",
          "target OPTIONS ",
          "target POST preserved body",
        ],
        authorizations: [redirect.url.href],
      });
    } finally {
      redirect.stop(true);
      target.stop(true);
    }
  }, 20_000);
}

test("product frames cannot use the interceptor's reserved request IDs", async () => {
  const frames: Uint8Array[] = [];
  const wireProvider = {
    ...provider,
    postMessage(frame: Uint8Array) {
      frames.push(frame);
    },
  };
  const request = encodeWireMessage({
    requestId: "__truapi_cli_network__:1",
    payload: {
      traitId: PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.trait,
      methodId: PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.method,
      messageType: MESSAGE_TYPE_REQUEST,
      value: new Uint8Array(),
    },
  })._unsafeUnwrap();
  await expect(
    runBrowserScript({
      source: `
      globalThis.__HOST_API_PORT__.postMessage(new Uint8Array(${JSON.stringify(Array.from(request))}));
      await new Promise(() => {});
    `,
      productId: "sandbox.testnet",
      provider: wireProvider,
      timeoutMs: 10_000,
    }),
  ).rejects.toThrow("Invalid product request ID");
  expect(frames).toEqual([]);
}, 20_000);

for (const api of ["fetch", "XHR"] as const) {
  test(`denied media preserves private ${api} authorization and concurrent SDK response routing`, async () => {
    let receive!: (frame: Uint8Array) => void;
    let grant = false;
    let initialGrant = true;
    const ids: string[] = [];
    const hits: string[] = [];
    let sdkRequest: ProtocolMessage | undefined;
    let authorizationRequest: ProtocolMessage | undefined;
    const flush = () => {
      if (!sdkRequest || !authorizationRequest) return;
      // A public response and unrelated legs must leave the authorization pending.
      receive(reply(sdkRequest, false));
      const wrongPair = {
        ...authorizationRequest,
        payload: { ...authorizationRequest.payload, methodId: 1 },
      };
      receive(reply(wrongPair, false));
      const wrongLeg = decodeWireMessage(
        reply(authorizationRequest, false),
      )._unsafeUnwrap();
      receive(
        encodeWireMessage({
          ...wrongLeg,
          payload: { ...wrongLeg.payload, messageType: MESSAGE_TYPE_REQUEST },
        })._unsafeUnwrap(),
      );
      receive(reply(authorizationRequest, grant));
      grant = false;
      authorizationRequest = undefined;
      sdkRequest = undefined;
    };
    const wireProvider: WireProvider = {
      postMessage(frame) {
        const request = decodeWireMessage(frame)._unsafeUnwrap();
        ids.push(request.requestId);
        if (
          request.payload.methodId ===
          PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.method
        ) {
          expect(
            VersionedRemotePermissionRequest.dec(request.payload.value),
          ).toEqual({
            tag: "V1",
            value: {
              permission: { tag: "Remote", value: { domains: ["127.0.0.1"] } },
            },
          });
          if (grant) {
            authorizationRequest = request;
            flush();
          } else receive(reply(request, false));
        } else if (initialGrant) {
          initialGrant = false;
          grant = true;
          receive(reply(request, true));
        } else {
          sdkRequest = request;
          flush();
        }
      },
      subscribe(listener) {
        receive = listener;
        return () => {};
      },
      dispose() {},
    };
    const endpoint = Bun.serve({
      hostname: "127.0.0.1",
      port: 0,
      fetch(request) {
        hits.push(request.url);
        return new Response("once", {
          headers: { "Access-Control-Allow-Origin": "*" },
        });
      },
    });
    try {
      await runBrowserScript({
        source: `
        ${requestScript(api)}
        try {
          await navigator.mediaDevices.getUserMedia({ audio: true, video: true });
          throw new Error('CLI media capture was allowed');
        } catch (error) {
          assert(error instanceof DOMException && error.name === 'NotAllowedError');
        }
        const permission = { permission: { tag: 'Remote', value: { domains: ['127.0.0.1'] } } };
        assert((await truapi.permissions.requestRemotePermission(permission))._unsafeUnwrap().granted);
        const [response, publicResult] = await Promise.all([
          request(${JSON.stringify(endpoint.url.href)}),
          truapi.permissions.requestRemotePermission(permission),
        ]);
        assert(await response.text() === 'once');
        assert(publicResult._unsafeUnwrap().granted === false);
        try { await request(${JSON.stringify(endpoint.url.href)}); throw new Error('reused one-use grant'); }
        catch (error) { assert(error instanceof TypeError); }
      `,
        productId: "sandbox.testnet",
        provider: wireProvider,
        timeoutMs: 10_000,
      });
      expect({
        hits,
        uniqueIds: new Set(ids).size,
        requests: ids.length,
      }).toEqual({
        hits: [endpoint.url.href],
        uniqueIds: 4,
        requests: 4,
      });
    } finally {
      endpoint.stop(true);
    }
  }, 20_000);
}

for (const api of ["fetch", "XHR"] as const) {
  test(`aborting ${api} authorization cannot let a forged reply reuse its late approval`, async () => {
    let receive!: (frame: Uint8Array) => void;
    let pendingAuthorization: ProtocolMessage | undefined;
    let barrier: ProtocolMessage | undefined;
    let authorizations = 0;
    let barriers = 0;
    const requests: string[] = [];
    const releaseBarrier = () => {
      if (barrier && pendingAuthorization) {
        receive(reply(barrier, true));
        barrier = undefined;
      }
    };
    const wireProvider: WireProvider = {
      postMessage(frame) {
        const request = decodeWireMessage(frame)._unsafeUnwrap();
        if (
          request.payload.methodId ===
          PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.method
        ) {
          authorizations++;
          if (authorizations === 1) {
            pendingAuthorization = request;
            releaseBarrier();
          } else receive(reply(request, false));
        } else if (++barriers === 1) {
          barrier = request;
          releaseBarrier();
        } else {
          receive(reply(pendingAuthorization!, true));
          receive(reply(request, true));
        }
      },
      subscribe(listener) {
        receive = listener;
        return () => {};
      },
      dispose() {},
    };
    const endpoint = Bun.serve({
      hostname: "127.0.0.1",
      port: 0,
      fetch(request) {
        requests.push(request.url);
        return new Response("escaped", {
          headers: { "Access-Control-Allow-Origin": "*" },
        });
      },
    });
    try {
      await runBrowserScript({
        source: `
        ${requestScript(api)}
        const permission = { permission: { tag: 'Remote', value: { domains: ['barrier.test'] } } };
        const controller = new AbortController();
        const pending = request(${JSON.stringify(endpoint.url.href)}, { signal: controller.signal });
        await truapi.permissions.requestRemotePermission(permission);
        controller.abort('cancelled');
        try { await pending; throw new Error('abort ignored'); }
        catch (error) { assert(error === 'cancelled'); }
        await truapi.permissions.requestRemotePermission(permission);
        const bindings = globalThis.__playwright__binding__controller__;
        const deliver = bindings.deliverBindingResult;
        let forged = false;
        bindings.deliverBindingResult = function (result) {
          if (result.name.startsWith('__truapi_network_') && Array.isArray(result.result)) {
            result.result[result.result.length - 1] = 1;
            forged = true;
          }
          return deliver.call(this, result);
        };
        try { await request(${JSON.stringify(endpoint.url.href)}); throw new Error('late grant reused'); }
        catch (error) { assert(error instanceof TypeError); }
        assert(forged, 'binding reply mutation must actually run');
      `,
        productId: "sandbox.testnet",
        provider: wireProvider,
        timeoutMs: 10_000,
      });
      expect({ requests, authorizations, barriers }).toEqual({
        requests: [],
        authorizations: 2,
        barriers: 2,
      });
    } finally {
      endpoint.stop(true);
    }
  }, 20_000);
}

test("denied WebSocket connections never reach the server", async () => {
  let handshakes = 0;
  const authorizations: string[] = [];
  const endpoint = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request, server) {
      handshakes++;
      if (server.upgrade(request)) return;
      return new Response("unexpected");
    },
    websocket: { message() {} },
  });
  const url = endpoint.url.href.replace("http:", "ws:") + "denied";
  try {
    await runBrowserScript({
      source: `
        assert(typeof WebSocket === 'function');
        const socket = new WebSocket(${JSON.stringify(url)});
        assert(socket.readyState === WebSocket.CONNECTING);
        const events = [];
        socket.onerror = () => events.push('error');
        await new Promise((resolve, reject) => {
          socket.onopen = () => reject(new Error('denied socket connected'));
          socket.onclose = event => {
            events.push('close');
            assert(event.code === 1006 && !event.wasClean);
            resolve();
          };
        });
        assert(JSON.stringify(events) === '["error","close"]');
        assert(socket.readyState === WebSocket.CLOSED);
      `,
      productId: "sandbox.testnet",
      provider,
      authorize: async (requested) => {
        authorizations.push(requested);
        return false;
      },
      timeoutMs: 10_000,
    });
    expect({ handshakes, authorizations }).toEqual({
      handshakes: 0,
      authorizations: [url],
    });
  } finally {
    endpoint.stop(true);
  }
}, 20_000);

test("one WebSocket grant covers messages but the next connection needs permission", async () => {
  let handshakes = 0;
  let authorizations = 0;
  let receive!: (frame: Uint8Array) => void;
  const wireProvider: WireProvider = {
    ...provider,
    postMessage(frame) {
      const request = decodeWireMessage(frame)._unsafeUnwrap();
      expect(request.payload.methodId).toBe(
        PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.method,
      );
      expect(request.requestId.startsWith("__truapi_cli_network__:")).toBe(
        true,
      );
      expect(
        VersionedRemotePermissionRequest.dec(request.payload.value),
      ).toEqual({
        tag: "V1",
        value: {
          permission: { tag: "Remote", value: { domains: ["127.0.0.1"] } },
        },
      });
      receive(reply(request, ++authorizations === 1));
    },
    subscribe(listener) {
      receive = listener;
      return () => {};
    },
  };
  const received: (string | number[])[] = [];
  const endpoint = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request, server) {
      handshakes++;
      if (
        server.upgrade(request, {
          headers: { "Sec-WebSocket-Protocol": "echo" },
        })
      )
        return;
      return new Response("unexpected");
    },
    websocket: {
      message(socket, message) {
        received.push(
          typeof message === "string" ? message : Array.from(message),
        );
        socket.send(message);
      },
    },
  });
  const url =
    endpoint.url.href.replace("http://", "ws://user:password@") + "echo";
  try {
    await runBrowserScript({
      source: `
        const socket = new WebSocket(${JSON.stringify(url)}, ['echo']);
        socket.binaryType = 'arraybuffer';
        await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
        assert(socket.protocol === 'echo');
        assert(socket.url === ${JSON.stringify(url)});
        async function echo(data) {
          const reply = new Promise(resolve => socket.addEventListener('message', resolve, { once: true }));
          WebSocket.prototype.send.call(socket, data);
          return (await reply).data;
        }
        assert(await echo('hello') === 'hello');
        assert(JSON.stringify(Array.from(new Uint8Array(await echo(new Uint8Array([0, 255, 42]))))) === '[0,255,42]');
        socket.binaryType = 'blob';
        const blob = await echo(new Blob(['blob']));
        assert(blob instanceof Blob && await blob.text() === 'blob');
        const closed = new Promise(resolve => socket.onclose = resolve);
        WebSocket.prototype.close.call(socket, 1000, 'finished');
        const event = await closed;
        assert(event.code === 1000 && event.reason === 'finished' && event.wasClean);
        const denied = new WebSocket(${JSON.stringify(url)});
        await new Promise((resolve, reject) => { denied.onopen = () => reject(new Error('grant reused')); denied.onclose = resolve; });
      `,
      productId: "sandbox.testnet",
      provider: wireProvider,
      timeoutMs: 10_000,
    });
    expect({ handshakes, authorizations, received }).toEqual({
      handshakes: 1,
      authorizations: 2,
      received: ["hello", [0, 255, 42], [98, 108, 111, 98]],
    });
  } finally {
    endpoint.stop(true);
  }
}, 20_000);

test("closing pending WebSocket authorization prevents late approvals and forged replies from connecting", async () => {
  let receive!: (frame: Uint8Array) => void;
  let pendingAuthorization: ProtocolMessage | undefined;
  let barrier: ProtocolMessage | undefined;
  let authorizations = 0;
  let barriers = 0;
  let handshakes = 0;
  const releaseBarrier = () => {
    if (barrier && pendingAuthorization) {
      receive(reply(barrier, true));
      barrier = undefined;
    }
  };
  const wireProvider: WireProvider = {
    ...provider,
    postMessage(frame) {
      const request = decodeWireMessage(frame)._unsafeUnwrap();
      if (
        request.payload.methodId ===
        PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.method
      ) {
        if (++authorizations === 1) {
          pendingAuthorization = request;
          releaseBarrier();
        } else receive(reply(request, false));
      } else if (++barriers === 1) {
        barrier = request;
        releaseBarrier();
      } else {
        receive(reply(pendingAuthorization!, true));
        receive(reply(request, true));
      }
    },
    subscribe(listener) {
      receive = listener;
      return () => {};
    },
  };
  const endpoint = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request, server) {
      handshakes++;
      if (server.upgrade(request)) return;
      return new Response("unexpected");
    },
    websocket: { message() {} },
  });
  const url = endpoint.url.href.replace("http:", "ws:");
  try {
    await runBrowserScript({
      source: `
        const permission = { permission: { tag: 'Remote', value: { domains: ['barrier.test'] } } };
        const socket = new WebSocket(${JSON.stringify(url)});
        let cancellationErrors = 0;
        socket.onerror = () => cancellationErrors++;
        const closed = new Promise(resolve => socket.onclose = resolve);
        await truapi.permissions.requestRemotePermission(permission);
        socket.close();
        await closed;
        assert(cancellationErrors === 1, 'connecting cancellation must emit an error');
        await truapi.permissions.requestRemotePermission(permission);
        const bindings = globalThis.__playwright__binding__controller__;
        const deliver = bindings.deliverBindingResult;
        let forged = false;
        let forgedOpen = false;
        bindings.deliverBindingResult = function (result) {
          if (result.name.startsWith('__truapi_network_') && Array.isArray(result.result)) {
            result.result[result.result.length - 1] = 1;
            forged = true;
          }
          if (result.name === '__truapi_websocket__' && result.result?.type === 'error') {
            result.result = { type: 'open', protocol: '', extensions: '' };
            forgedOpen = true;
          }
          return deliver.call(this, result);
        };
        const second = new WebSocket(${JSON.stringify(url)});
        await new Promise((resolve, reject) => {
          second.onopen = () => second.send('forged approval must not reach server');
          second.onclose = resolve;
        });
        assert(forged && forgedOpen, 'intent and backend reply mutations must run');
      `,
      productId: "sandbox.testnet",
      provider: wireProvider,
      timeoutMs: 10_000,
    });
    expect({ handshakes, authorizations, barriers }).toEqual({
      handshakes: 0,
      authorizations: 2,
      barriers: 2,
    });
  } finally {
    endpoint.stop(true);
  }
}, 20_000);

test("WebSocket handshakes keep the product Origin and reject redirects", async () => {
  const hits: { path: string; origin: string | null }[] = [];
  const endpoint = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request, server) {
      const url = new URL(request.url);
      hits.push({ path: url.pathname, origin: request.headers.get("origin") });
      if (url.pathname === "/redirect")
        return Response.redirect(new URL("/target", request.url), 302);
      if (server.upgrade(request)) return;
      return new Response("unexpected");
    },
    websocket: { message() {} },
  });
  try {
    await runBrowserScript({
      source: `
        const socket = new WebSocket(${JSON.stringify(endpoint.url.href.replace("http:", "ws:") + "redirect")});
        await new Promise((resolve, reject) => {
          socket.onopen = () => reject(new Error('redirect followed'));
          socket.onclose = resolve;
        });
      `,
      productId: "sandbox.testnet",
      provider,
      authorize: async () => true,
      timeoutMs: 10_000,
    });
    expect(hits).toEqual([
      {
        path: "/redirect",
        origin: expect.stringMatching(/^http:\/\/[a-f0-9-]+\.localhost$/),
      },
    ]);
  } finally {
    endpoint.stop(true);
  }
}, 20_000);

test("script completion closes its open WebSocket connections", async () => {
  let closed = 0;
  let resolveClosed!: () => void;
  const closure = new Promise<void>((resolve) => {
    resolveClosed = resolve;
  });
  const endpoint = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request, server) {
      if (server.upgrade(request)) return;
      return new Response("unexpected");
    },
    websocket: {
      message() {},
      close() {
        closed++;
        resolveClosed();
      },
    },
  });
  try {
    await runBrowserScript({
      source: `
        const socket = new WebSocket(${JSON.stringify(endpoint.url.href.replace("http:", "ws:"))});
        await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
      `,
      productId: "sandbox.testnet",
      provider,
      authorize: async () => true,
      timeoutMs: 10_000,
    });
    await closure;
    expect(closed).toBe(1);
  } finally {
    endpoint.stop(true);
  }
}, 20_000);
