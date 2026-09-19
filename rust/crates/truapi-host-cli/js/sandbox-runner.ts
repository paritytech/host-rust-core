import { chromium, type CDPSession, type Page } from "playwright-core";
import { fileURLToPath } from "node:url";
import {
  decodeWireMessage,
  encodeWireMessage,
  MESSAGE_TYPE_REQUEST,
  MESSAGE_TYPE_RESPONSE,
  scale,
  VersionedRemotePermissionRequest,
  VersionedRemotePermissionResponse,
  VersionedRemotePermissionError,
  type WireProvider,
} from "../../../../js/packages/truapi/src/index.ts";
import { PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION } from "../../../../js/packages/truapi/src/generated/wire-table.ts";
import { buildProductScript } from "./sandbox-build.ts";
import { buildBrowserAssets, type BrowserAssets } from "./browser-assets.ts";
import { wsProvider } from "./ws-provider.ts";
import {
  createWebSocketBroker,
  installWebSocketBackend,
  type Authorization,
} from "./sandbox-websocket.ts";

export interface BrowserScriptOptions {
  source: string;
  productId: string;
  authorize?: (url: string) => Promise<boolean>;
  provider: WireProvider;
  onConsole?: (level: string, message: string) => void;
  timeoutMs?: number;
}

let assetPromise: Promise<BrowserAssets> | undefined;
const authorizationPrefix = "__truapi_cli_network__:";
const authorizationResponse = scale.Result(
  VersionedRemotePermissionResponse,
  scale.CallError(VersionedRemotePermissionError),
);

interface NetworkOperation {
  url: string;
  active: boolean;
  authorization?: Authorization;
}
export function browserAssets(): Promise<BrowserAssets> {
  return (assetPromise ??= (async () => {
    const directory = new URL("./sandbox-assets/", import.meta.url);
    if (await Bun.file(new URL("container.js", directory)).exists()) {
      const [container, client, bootstrap] = await Promise.all([
        Bun.file(new URL("container.js", directory)).text(),
        Bun.file(new URL("client.mjs", directory)).text(),
        Bun.file(new URL("bootstrap.js", directory)).text(),
      ]);
      return { container, client, bootstrap };
    }
    if (import.meta.url.endsWith("/runner.js")) {
      throw new Error(
        "Sandbox assets are missing beside runner.js; reinstall truapi-host",
      );
    }
    return buildBrowserAssets(
      fileURLToPath(new URL("../../../../", import.meta.url)),
    );
  })());
}

function browserEnvironment(): Record<string, string> {
  const environment: Record<string, string> = {};
  for (const name of [
    "PATH",
    "LANG",
    "LC_ALL",
    "LD_LIBRARY_PATH",
    "SYSTEMROOT",
    "TMPDIR",
  ]) {
    if (process.env[name]) environment[name] = process.env[name]!;
  }
  return environment;
}

export async function runBrowserScript(
  options: BrowserScriptOptions,
): Promise<void> {
  const assets = await browserAssets();
  const origin = `http://${crypto.randomUUID()}.localhost`;
  const nonce = crypto.randomUUID();
  const headers = [
    {
      name: "Content-Security-Policy",
      value: `sandbox allow-scripts allow-same-origin; default-src 'none'; script-src 'self' 'wasm-unsafe-eval' 'nonce-${nonce}'; connect-src http: https:; img-src http: https: data:; style-src 'unsafe-inline'; worker-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'`,
    },
    { name: "X-DNS-Prefetch-Control", value: "off" },
    { name: "Cache-Control", value: "no-store" },
    { name: "Referrer-Policy", value: "no-referrer" },
  ];
  const resources = new Map([
    [
      "/",
      {
        type: "text/html",
        body: `<!doctype html><meta charset="utf-8"><title>TrUAPI product</title><script type="importmap" nonce="${nonce}">{"imports":{"@parity/truapi":"${origin}/client.mjs"}}</script>`,
      },
    ],
    ["/client.mjs", { type: "text/javascript", body: assets.client }],
    ["/bootstrap.js", { type: "text/javascript", body: assets.bootstrap }],
    ["/product.mjs", { type: "text/javascript", body: options.source }],
  ]);
  let browser;
  try {
    browser = await chromium.launch({
      headless: true,
      chromiumSandbox: true,
      env: browserEnvironment(),
      args: ["--dns-prefetch-disable", "--disable-quic"],
    });
  } catch (error) {
    throw new Error(
      `Cannot start the sandboxed product browser. Run truapi-host install-browser and ensure Chromium sandboxing is supported. ${String(error)}`,
    );
  }
  let unsubscribe: (() => void) | undefined;
  let unsubscribeClose: (() => void) | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let done = false;
  let failed = false;
  let resolveDone!: () => void;
  let rejectDone!: (error: Error) => void;
  const completion = new Promise<void>((resolve, reject) => {
    resolveDone = resolve;
    rejectDone = reject;
  });
  const privateRequests = new Map<string, (allowed: boolean) => void>();
  const authorizationSession = crypto.randomUUID();
  let authorizationSequence = 0;
  const operations = new Map<string, NetworkOperation>();
  const networkRequests = new Map<
    string,
    {
      ready: Promise<NetworkOperation | undefined>;
      resolve: (operation?: NetworkOperation) => void;
    }
  >();
  const webSockets = createWebSocketBroker(authorizeNetworkRequest, origin);
  // Startup can fail before the caller begins awaiting script completion.
  void completion.catch(() => {});
  const fail = (error: unknown) => {
    if (done) return;
    done = true;
    rejectDone(error instanceof Error ? error : new Error(String(error)));
  };
  try {
    const context = await browser.newContext({
      serviceWorkers: "block",
      acceptDownloads: false,
    });
    await context.grantPermissions(["local-network-access"], { origin });
    const page = await context.newPage();
    context.on("page", (other) => {
      if (other !== page) void other.close();
    });
    page.on("crash", () => fail(new Error("Product browser crashed")));
    page.on("close", () =>
      fail(new Error("Product browser closed before completion")),
    );
    page.on("pageerror", fail);
    page.on("console", (message) =>
      options.onConsole?.(message.type(), message.text()),
    );
    const session = await context.newCDPSession(page);
    session.on("Network.requestWillBeSent", (event) => {
      const request = networkRequest(event.requestId);
      const needsAuthorization = event.type === "Fetch" || event.type === "XHR";
      if (needsAuthorization && !operations.has(event.requestId)) {
        const operation = { url: event.request.url, active: true };
        operations.set(event.requestId, operation);
        request.resolve(operation);
      } else if (
        event.initiator.type === "preflight" &&
        event.initiator.requestId
      ) {
        void networkRequest(event.initiator.requestId).ready.then(
          request.resolve,
        );
      } else if (!needsAuthorization) {
        request.resolve();
      }
    });
    const finishNetworkRequest = ({ requestId }: { requestId: string }) => {
      const operation = operations.get(requestId);
      if (operation) {
        operation.active = false;
        operation.authorization?.cancel();
        operations.delete(requestId);
      }
      networkRequests.get(requestId)?.resolve();
      networkRequests.delete(requestId);
    };
    session.on("Network.loadingFinished", finishNetworkRequest);
    session.on("Network.loadingFailed", finishNetworkRequest);
    let firstDocument = true;
    session.on("Fetch.requestPaused", (event) => {
      let operation: NetworkOperation | undefined;
      void (async () => {
        const url = new URL(event.request.url);
        if (event.resourceType === "Document") {
          if (!firstDocument || url.href !== `${origin}/`)
            return denyRequest(session, event.requestId);
          firstDocument = false;
        }
        if (url.origin === origin) {
          const resource = !url.search
            ? resources.get(url.pathname)
            : undefined;
          if (!resource) return denyRequest(session, event.requestId);
          await session.send("Fetch.fulfillRequest", {
            requestId: event.requestId,
            responseCode: 200,
            responseHeaders: [
              ...headers,
              { name: "Content-Type", value: resource.type },
            ],
            body: Buffer.from(resource.body).toString("base64"),
          });
        } else {
          if (["http:", "https:"].includes(url.protocol) && event.networkId) {
            operation = await networkRequest(event.networkId).ready;
            if (operation?.active) {
              operation.authorization ??= authorizeNetworkRequest(
                operation.url,
              );
              const allowed = await operation.authorization.result;
              if (!operation.active) return;
              if (allowed) {
                await session.send("Fetch.continueRequest", {
                  requestId: event.requestId,
                });
                return;
              }
            }
          }
          await denyRequest(session, event.requestId);
        }
      })().catch((error) => {
        if (done || operation?.active === false) return;
        void denyRequest(session, event.requestId).catch(() => {});
        fail(error);
      });
    });
    await session.send("Network.enable");
    await session.send("Fetch.enable", {
      patterns: [{ urlPattern: "*", requestStage: "Request" }],
    });

    await page.exposeBinding(
      "__truapi_websocket__",
      ({ frame }, command: unknown) => {
        if (frame !== page.mainFrame())
          throw new Error("Invalid WebSocket frame");
        return webSockets.command(command);
      },
    );
    await page.exposeBinding(
      "__truapi_network_intent__",
      ({ frame }, input: unknown) => {
        if (frame !== page.mainFrame() || !isFrame(input))
          throw new Error("Invalid authorization frame");
        const decoded = decodeWireMessage(Uint8Array.from(input));
        if (decoded.isErr()) throw decoded.error;
        const request = decoded.value;
        if (
          request.payload.traitId !==
            PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.trait ||
          request.payload.methodId !==
            PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.method ||
          request.payload.messageType !== MESSAGE_TYPE_REQUEST
        )
          throw new Error("Invalid authorization method");
        const { permission } = VersionedRemotePermissionRequest.dec(
          request.payload.value,
        ).value;
        // CLI authorization belongs to the intercepted request, so cancellation cannot leave a reusable grant.
        const granted =
          permission.tag === "Remote" &&
          permission.value.domains.length === 1 &&
          permission.value.domains[0] !== "" &&
          !permission.value.domains[0].includes("*");
        const response = encodeWireMessage({
          requestId: request.requestId,
          payload: {
            ...request.payload,
            messageType: MESSAGE_TYPE_RESPONSE,
            value: authorizationResponse.enc({
              success: true,
              value: { tag: "V1", value: { granted } },
            }),
          },
        });
        if (response.isErr()) throw response.error;
        return Array.from(response.value);
      },
    );
    await page.exposeBinding(
      "__truapi_send__",
      ({ frame }, message: unknown) => {
        if (frame !== page.mainFrame() || !isFrame(message)) {
          throw new Error("Invalid product frame");
        }
        const bytes = Uint8Array.from(message);
        const decoded = decodeWireMessage(bytes);
        if (
          decoded.isErr() ||
          decoded.value.requestId.startsWith(authorizationPrefix)
        ) {
          throw new Error("Invalid product request ID");
        }
        options.provider.postMessage(bytes);
      },
    );
    await page.exposeBinding(
      "__truapi_complete__",
      ({ frame }, error: unknown) => {
        if (frame !== page.mainFrame() || done) return;
        if (error !== null) return fail(new Error(String(error)));
        done = true;
        resolveDone();
      },
    );
    const bootstrap = `(() => {
      if (window !== window.top) return;
      const send = window.__truapi_send__;
      const sendNetwork = window.__truapi_network_intent__;
      const apply = Reflect.apply;
      const then = Promise.prototype.then;
      const from = Array.from;
      const Bytes = Uint8Array;
      const networkPort = {
        onmessage: null,
        onmessageerror: null,
        postMessage(message) {
          apply(then, sendNetwork(from(message)), [
            bytes => networkPort.onmessage?.({ data: new Bytes(bytes) }),
            () => networkPort.onmessageerror?.(),
          ]);
        },
      };
      const channel = new MessageChannel();
      channel.port2.onmessage = event => send(Array.from(new Uint8Array(event.data)));
      channel.port2.start();
      window.addEventListener('__truapi_frame__', event => channel.port2.postMessage(new Uint8Array(event.detail)));
      window.__HOST_API_PORT__ = channel.port1;
      window.__HOST_WEBVIEW_MARK__ = true;
      window.__truapi_product_id__ = ${JSON.stringify(options.productId)};
      window.__truapi_network_port__ = networkPort;
      window.__truapi_policy__ = { webRtcAllowed: false, mediaAllowed: false };
      delete window.__truapi_network_intent__;
      delete window.__truapi_send__;
    })();`;
    await page.addInitScript({
      content: `${bootstrap}\n(${installWebSocketBackend.toString()})();\n${assets.container}`,
    });
    let ready = false;
    const pending: Uint8Array[] = [];
    unsubscribe = options.provider.subscribe((message) => {
      const decoded = decodeWireMessage(message);
      if (
        decoded.isOk() &&
        decoded.value.requestId.startsWith(authorizationPrefix)
      ) {
        const { requestId, payload } = decoded.value;
        if (
          payload.traitId !== PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.trait ||
          payload.methodId !== PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.method ||
          payload.messageType !== MESSAGE_TYPE_RESPONSE
        )
          return;
        const finish = privateRequests.get(requestId);
        if (!finish) return;
        try {
          const response = authorizationResponse.dec(payload.value);
          finish(response.success && response.value.value.granted);
        } catch {
          finish(false);
        }
        return;
      }
      if (ready) void deliverFrame(page, message).catch(fail);
      else pending.push(message.slice());
    });
    unsubscribeClose = options.provider.subscribeClose?.((error) =>
      fail(error),
    );
    timer = setTimeout(
      () => fail(new Error("Product script timed out")),
      options.timeoutMs ?? 300_000,
    );
    await page.goto(`${origin}/`);
    ready = true;
    for (const message of pending.splice(0)) await deliverFrame(page, message);
    void page
      .addScriptTag({ type: "module", url: `${origin}/bootstrap.js` })
      .catch(fail);
    await completion;
  } catch (error) {
    failed = true;
    throw error;
  } finally {
    done = true;
    if (timer) clearTimeout(timer);
    unsubscribe?.();
    unsubscribeClose?.();
    webSockets.dispose();
    for (const finish of privateRequests.values()) finish(false);
    for (const operation of operations.values()) operation.active = false;
    for (const request of networkRequests.values()) request.resolve();
    operations.clear();
    networkRequests.clear();
    try {
      await browser.close();
    } catch (error) {
      if (!failed) throw error;
    }
  }

  function networkRequest(requestId: string) {
    // Chromium can pause a request before its Network metadata arrives.
    let request = networkRequests.get(requestId);
    if (!request) {
      let resolve!: (operation?: NetworkOperation) => void;
      const ready = new Promise<NetworkOperation | undefined>((done) => {
        resolve = done;
      });
      request = { ready, resolve };
      networkRequests.set(requestId, request);
    }
    return request;
  }

  function authorizeNetworkRequest(url: string): Authorization {
    if (options.authorize) {
      return {
        result: Promise.resolve()
          .then(() => options.authorize!(url))
          .catch(() => false),
        cancel() {},
      };
    }
    const requestId = `${authorizationPrefix}${authorizationSession}:${++authorizationSequence}`;
    let finish!: (allowed: boolean) => void;
    const result = new Promise<boolean>((resolve) => {
      const timeout = setTimeout(() => finish(false), 120_000);
      finish = (allowed) => {
        clearTimeout(timeout);
        privateRequests.delete(requestId);
        resolve(allowed);
      };
      privateRequests.set(requestId, finish);
      try {
        const destination = new URL(url);
        if (
          !["http:", "https:", "ws:", "wss:"].includes(destination.protocol) ||
          !destination.hostname ||
          destination.hostname.includes("*")
        )
          throw new Error(
            "Network access requires a concrete HTTP(S) or WS(S) URL",
          );
        const request = encodeWireMessage({
          requestId,
          payload: {
            traitId: PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.trait,
            methodId: PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION.method,
            messageType: MESSAGE_TYPE_REQUEST,
            value: VersionedRemotePermissionRequest.enc({
              tag: "V1",
              value: {
                permission: {
                  tag: "Remote",
                  value: { domains: [destination.hostname] },
                },
              },
            }),
          },
        })._unsafeUnwrap();
        options.provider.postMessage(request);
      } catch {
        finish(false);
      }
    });
    return { result, cancel: () => finish(false) };
  }
}

function isFrame(value: unknown): value is number[] {
  return (
    Array.isArray(value) &&
    value.length <= 64 * 1024 * 1024 &&
    value.every((byte) => Number.isInteger(byte) && byte >= 0 && byte <= 255)
  );
}

async function denyRequest(
  session: CDPSession,
  requestId: string,
): Promise<void> {
  await session.send("Fetch.failRequest", {
    requestId,
    errorReason: "BlockedByClient",
  });
}

async function deliverFrame(page: Page, message: Uint8Array): Promise<void> {
  await page.evaluate(
    (bytes) =>
      window.dispatchEvent(
        new CustomEvent("__truapi_frame__", { detail: bytes }),
      ),
    Array.from(message),
  );
}

export async function runSandboxScript(
  frameUrl: string,
  productId: string,
  scriptPath: string,
): Promise<void> {
  const source = await buildProductScript(scriptPath);
  const provider = wsProvider(frameUrl);
  const timer = setTimeout(() => {
    console.error(`[runner] timed out connecting to ${frameUrl}`);
    process.exit(2);
  }, 15_000);
  try {
    await provider.opened;
    clearTimeout(timer);
    await runBrowserScript({
      source,
      productId,
      provider,
      onConsole: (level, message) =>
        (level === "error" || level === "warning"
          ? console.error
          : console.log)(message),
    });
  } finally {
    clearTimeout(timer);
    provider.dispose();
  }
}
