import { afterEach, describe, expect, it, mock } from "bun:test";

import { encodeWireMessage } from "./transport.js";

let importCounter = 0;

async function importSandbox(): Promise<typeof import("./sandbox.js")> {
    importCounter += 1;
    return import(`./sandbox.ts?test=${importCounter}`);
}

type MessageListener = (event: MessageEvent) => void;

function installFakeIframeWindow(options: { referrer?: string; ancestorOrigins?: string[] }) {
    const listeners = new Set<MessageListener>();
    const priorWindow = globalThis.window;
    const priorDocument = globalThis.document;
    const parentPostMessage = mock((_message: unknown, _origin: string) => {});
    const parent = {
        postMessage: parentPostMessage,
    } as unknown as Window;
    const win = {
        parent,
        top: {} as Window,
        location: {
            ancestorOrigins: options.ancestorOrigins,
        },
        addEventListener(name: string, callback: EventListener) {
            if (name === "message") listeners.add(callback as MessageListener);
        },
        removeEventListener(name: string, callback: EventListener) {
            if (name === "message") listeners.delete(callback as MessageListener);
        },
    } as unknown as Window & typeof globalThis;

    globalThis.window = win;
    globalThis.document = {
        referrer: options.referrer ?? "",
    } as Document;

    return {
        listeners,
        parent,
        parentPostMessage,
        win,
        dispatch(event: { source: unknown; origin: string; data: unknown; ports?: MessagePort[] }) {
            for (const listener of [...listeners]) {
                listener({ ports: [], ...event } as MessageEvent);
            }
        },
        restore() {
            if (priorWindow === undefined) {
                delete (globalThis as { window?: unknown }).window;
            } else {
                globalThis.window = priorWindow;
            }
            if (priorDocument === undefined) {
                delete (globalThis as { document?: unknown }).document;
            } else {
                globalThis.document = priorDocument;
            }
        },
    };
}

let currentWindow: ReturnType<typeof installFakeIframeWindow> | null = null;
const openPorts: MessagePort[] = [];

function trackChannel(): MessageChannel {
    const channel = new MessageChannel();
    openPorts.push(channel.port1, channel.port2);
    return channel;
}

afterEach(() => {
    for (const port of openPorts.splice(0)) {
        port.close();
    }
    currentWindow?.restore();
    currentWindow = null;
});

describe("sandbox iframe MessagePort handshake", () => {
    it("posts ready to the resolved host origin and rejects non-parent or mismatched init messages", async () => {
        currentWindow = installFakeIframeWindow({
            referrer: "https://host.example/product",
        });
        const sandbox = await importSandbox();

        expect(sandbox.getClientSync()).not.toBeNull();
        expect(currentWindow.parentPostMessage.mock.calls).toEqual([
            [{ type: "truapi-ready" }, "https://host.example"],
        ]);

        const wrongSource = trackChannel();
        currentWindow.dispatch({
            source: {},
            origin: "https://host.example",
            data: { type: "truapi-init" },
            ports: [wrongSource.port1],
        });
        const wrongOrigin = trackChannel();
        currentWindow.dispatch({
            source: currentWindow.parent,
            origin: "https://attacker.example",
            data: { type: "truapi-init" },
            ports: [wrongOrigin.port1],
        });
        const opaqueOrigin = trackChannel();
        currentWindow.dispatch({
            source: currentWindow.parent,
            origin: "null",
            data: { type: "truapi-init" },
            ports: [opaqueOrigin.port1],
        });
        await Promise.resolve();
        expect(currentWindow.win.__HOST_API_PORT__).toBeUndefined();
        expect(currentWindow.listeners.size).toBe(1);

        const accepted = trackChannel();
        currentWindow.dispatch({
            source: currentWindow.parent,
            origin: "https://host.example",
            data: { type: "truapi-init" },
            ports: [accepted.port1],
        });
        await Promise.resolve();
        expect(currentWindow.win.__HOST_API_PORT__).toBe(accepted.port1);
        expect(currentWindow.listeners.size).toBe(0);
    });

    it('treats a masked "null" ancestor origin as hidden and pings with the wildcard', async () => {
        // Firefox implements location.ancestorOrigins but serializes cross-origin
        // ancestors as "null", which is not a valid postMessage targetOrigin.
        currentWindow = installFakeIframeWindow({ ancestorOrigins: ["null"] });
        const sandbox = await importSandbox();

        expect(sandbox.getClientSync()).not.toBeNull();
        expect(currentWindow.parentPostMessage.mock.calls).toEqual([
            [{ type: "truapi-ready" }, "*"],
        ]);

        const accepted = trackChannel();
        currentWindow.dispatch({
            source: currentWindow.parent,
            origin: "https://host.example",
            data: { type: "truapi-init" },
            ports: [accepted.port1],
        });
        await Promise.resolve();
        expect(currentWindow.win.__HOST_API_PORT__).toBe(accepted.port1);
        expect(currentWindow.listeners.size).toBe(0);
    });

    it("uses a data-free wildcard ready ping only when the host origin is hidden", async () => {
        currentWindow = installFakeIframeWindow({});
        const sandbox = await importSandbox();

        expect(sandbox.getClientSync()).not.toBeNull();
        expect(currentWindow.parentPostMessage.mock.calls).toEqual([
            [{ type: "truapi-ready" }, "*"],
        ]);

        const wrongSource = trackChannel();
        currentWindow.dispatch({
            source: {},
            origin: "https://host.example",
            data: { type: "truapi-init" },
            ports: [wrongSource.port1],
        });
        await Promise.resolve();
        expect(currentWindow.win.__HOST_API_PORT__).toBeUndefined();

        const accepted = trackChannel();
        currentWindow.dispatch({
            source: currentWindow.parent,
            origin: "https://host.example",
            data: { type: "truapi-init" },
            ports: [accepted.port1],
        });
        await Promise.resolve();
        expect(currentWindow.win.__HOST_API_PORT__).toBe(accepted.port1);
        expect(currentWindow.listeners.size).toBe(0);
    });

    it("reports connecting until the MessagePort handover completes", async () => {
        currentWindow = installFakeIframeWindow({
            referrer: "https://host.example/product",
        });
        const sandbox = await importSandbox();
        const statuses: string[] = [];
        sandbox.subscribeConnectionStatus((status) => statuses.push(status));
        expect(statuses).toEqual(["connecting"]);

        const accepted = trackChannel();
        currentWindow.dispatch({
            source: currentWindow.parent,
            origin: "https://host.example",
            data: { type: "truapi-init" },
            ports: [accepted.port1],
        });
        expect(statuses).toEqual(["connecting", "connected"]);
    });

    it("reports connecting until the first legacy frame pins the transport", async () => {
        currentWindow = installFakeIframeWindow({
            referrer: "https://legacy-host.example/product",
        });
        const sandbox = await importSandbox();
        const statuses: string[] = [];
        sandbox.subscribeConnectionStatus((status) => statuses.push(status));
        expect(statuses).toEqual(["connecting"]);

        const probe = encodeWireMessage({
            requestId: "legacy-probe",
            payload: { id: 255, value: new Uint8Array() },
        });
        expect(probe.isOk()).toBe(true);
        if (probe.isErr()) throw probe.error;
        currentWindow.dispatch({
            source: currentWindow.parent,
            origin: "https://legacy-host.example",
            data: probe.value,
        });
        expect(statuses).toEqual(["connecting", "connected"]);
    });

    it("reports connected immediately when the host port is already injected", async () => {
        currentWindow = installFakeIframeWindow({
            referrer: "https://host.example/product",
        });
        const channel = trackChannel();
        currentWindow.win.__HOST_API_PORT__ = channel.port1;
        const sandbox = await importSandbox();
        const statuses: string[] = [];
        sandbox.subscribeConnectionStatus((status) => statuses.push(status));
        expect(statuses).toEqual(["connected"]);
    });

    it("falls back to legacy window frames and pins their parent origin", async () => {
        currentWindow = installFakeIframeWindow({
            referrer: "https://legacy-host.example/product",
        });
        const sandbox = await importSandbox();
        const client = sandbox.getClientSync();
        expect(client).not.toBeNull();

        const probe = encodeWireMessage({
            requestId: "legacy-probe",
            payload: { id: 255, value: new Uint8Array() },
        });
        expect(probe.isOk()).toBe(true);
        if (probe.isErr()) throw probe.error;
        currentWindow.dispatch({
            source: currentWindow.parent,
            origin: "https://legacy-host.example",
            data: probe.value,
        });

        void client?.system.handshake();
        expect(currentWindow.parentPostMessage.mock.calls).toHaveLength(2);
        expect(currentWindow.parentPostMessage.mock.calls[1][0]).toBeInstanceOf(Uint8Array);
        expect(currentWindow.parentPostMessage.mock.calls[1][1]).toBe(
            "https://legacy-host.example",
        );
    });
});

describe("connectWebSocketHost", () => {
    const servers: ReturnType<typeof Bun.serve>[] = [];

    afterEach(() => {
        for (const server of servers.splice(0)) server.stop(true);
    });

    /** Loopback frame socket, standing in for `truapi-host --frame-listen`. */
    function frameServer() {
        const server = Bun.serve({
            hostname: "127.0.0.1",
            port: 0,
            fetch(request, server) {
                if (server.upgrade(request)) return;
                return new Response("websocket upgrade required", { status: 426 });
            },
            websocket: {
                message() {},
            },
        });
        servers.push(server);
        return `ws://127.0.0.1:${server.port}`;
    }

    it("makes a plain page count as hosted and caches one client", async () => {
        const sandbox = await importSandbox();
        expect(sandbox.isCorrectEnvironment()).toBe(false);

        const client = sandbox.connectWebSocketHost(frameServer());

        expect(sandbox.isCorrectEnvironment()).toBe(true);
        expect(client).not.toBeNull();
        expect(sandbox.getClientSync()).toBe(client);
    });

    it("reports connected once the socket is open", async () => {
        const sandbox = await importSandbox();
        const statuses: string[] = [];
        const connected = new Promise<void>((resolve) => {
            sandbox.subscribeConnectionStatus((status) => {
                statuses.push(status);
                if (status === "connected") resolve();
            });
        });

        sandbox.connectWebSocketHost(frameServer());
        await connected;

        expect(statuses).toContain("connected");
    });

    it("refuses to redirect a client that already exists", async () => {
        const sandbox = await importSandbox();
        sandbox.connectWebSocketHost(frameServer());

        expect(() => sandbox.connectWebSocketHost(frameServer())).toThrow(
            /before the TrUAPI client is created/,
        );
    });
});

/** The transport adopts its port off a promise, not inline. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

function closePipe(port: MessagePort): void {
    const hook = port.onmessageerror;
    if (!hook) throw new Error("no messageerror hook installed on the port");
    hook.call(port, new MessageEvent("messageerror"));
}

function installFakeWebviewWindow() {
    const harness = installFakeIframeWindow({});
    // Top-level, so isIframe() reads false.
    (harness.win as unknown as { top: Window }).top = harness.win;
    harness.win.__HOST_WEBVIEW_MARK__ = true;
    return harness;
}

describe("sandbox after the pipe closes", () => {
    async function connectedSandbox(port: MessagePort) {
        const harness = installFakeIframeWindow({
            referrer: "https://host.example/product",
        });
        currentWindow = harness;
        const sandbox = await importSandbox();
        // After the import: a stale module still closing would clear this global.
        harness.win.__HOST_API_PORT__ = port;
        const client = sandbox.getClientSync();
        expect(client).not.toBeNull();
        await settle();
        return { client, harness, sandbox };
    }

    it("gives a subscriber arriving after a close a negotiation that can complete", async () => {
        const channel = trackChannel();
        const { harness, sandbox } = await connectedSandbox(channel.port1);
        closePipe(channel.port1);

        const statuses: string[] = [];
        sandbox.subscribeConnectionStatus((status) => statuses.push(status));
        expect(statuses).toEqual(["connecting"]);

        const rebuilt = trackChannel();
        harness.dispatch({
            source: harness.parent,
            origin: "https://host.example",
            data: { type: "truapi-init" },
            ports: [rebuilt.port1],
        });

        // Pre-fix this "connecting" was permanent: nothing listened for the answer.
        expect(statuses).toEqual(["connecting", "connected"]);
    });

    it("builds a new client after a close instead of handing back the closed one", async () => {
        const channel = trackChannel();
        const { client, sandbox } = await connectedSandbox(channel.port1);
        closePipe(channel.port1);

        const rebuilt = sandbox.getClientSync();

        expect(rebuilt).not.toBeNull();
        expect(rebuilt).not.toBe(client);
    });

    it("drops the injected port so a rebuild cannot re-adopt the closed one", async () => {
        const channel = trackChannel();
        const { harness } = await connectedSandbox(channel.port1);
        expect(harness.win.__HOST_API_PORT__).toBe(channel.port1);

        closePipe(channel.port1);

        expect(harness.win.__HOST_API_PORT__).toBeUndefined();
    });

    it("renegotiates with the parent on the next build", async () => {
        const channel = trackChannel();
        const { harness, sandbox } = await connectedSandbox(channel.port1);
        // An injected port skips the handshake, so nothing was posted yet.
        expect(harness.parentPostMessage.mock.calls).toEqual([]);

        closePipe(channel.port1);
        sandbox.getClientSync();

        expect(harness.parentPostMessage.mock.calls).toEqual([
            [{ type: "truapi-ready" }, "https://host.example"],
        ]);
    });

    it("does not hand the closed client to a listener notified of the close", async () => {
        const channel = trackChannel();
        const { client, sandbox } = await connectedSandbox(channel.port1);
        const seen: unknown[] = [];
        sandbox.subscribeConnectionStatus((status) => {
            if (status === "disconnected") seen.push(sandbox.getClientSync());
        });

        closePipe(channel.port1);

        expect(seen).toHaveLength(1);
        expect(seen[0]).not.toBeNull();
        expect(seen[0]).not.toBe(client);
    });

    it("keeps a marked webview page hosted after the port is dropped", async () => {
        const channel = trackChannel();
        const harness = installFakeWebviewWindow();
        currentWindow = harness;
        const sandbox = await importSandbox();
        harness.win.__HOST_API_PORT__ = channel.port1;
        expect(sandbox.isCorrectEnvironment()).toBe(true);
        expect(sandbox.getClientSync()).not.toBeNull();
        await settle();

        closePipe(channel.port1);

        expect(harness.win.__HOST_API_PORT__).toBeUndefined();
        expect(sandbox.isCorrectEnvironment()).toBe(true);
    });
});
