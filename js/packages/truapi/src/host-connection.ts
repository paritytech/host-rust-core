import { createTransport } from "./client.js";
import { createClient, type TrUApiClient } from "./generated/client.js";
import {
  createInternalClient,
  type InternalTrUApiClient,
} from "./generated/internal-client.js";
import { SYSTEM_HANDSHAKE } from "./generated/wire-table.js";
import type { ConnectionStatus } from "./sandbox.js";
import {
  ConnectionResetError,
  createWebSocketProviderFactory,
  decodeWireMessage,
  type WebSocketWireProvider,
} from "./transport.js";

/** One native host connection shared by product calls and browser authorization. */
export interface HostConnection {
  /** Stable public client. Reading it also connects passive host-initiated handlers. */
  readonly client: TrUApiClient;
  /** Private generated authorization methods on the same transport. */
  readonly internal: InternalTrUApiClient;
  /** Startup compatibility for SDKs predating the injected client. */
  readonly legacyPort: MessagePort;
  /** Observe connection readiness without replacing the client. */
  subscribeConnectionStatus(
    callback: (status: ConnectionStatus) => void,
  ): () => void;
  /** End this execution's connection permanently. */
  dispose(): void;
}

interface Connection {
  provider: WebSocketWireProvider;
  verified: boolean;
  checkedAt: number;
  checking?: Promise<void>;
}

/** Creates a client whose interrupted operations fail and whose later calls reconnect. */
export function createHostConnection(url: string): HostConnection {
  const createProvider = createWebSocketProviderFactory();
  let current: Connection | undefined;
  let stopped = false;
  let receive: ((frame: Uint8Array) => void) | undefined;
  let reset: ((error: Error) => void) | undefined;
  let legacy: { receive(frame: Uint8Array): void; close(): void } | undefined;
  let legacyPort: MessagePort | undefined;
  let status: ConnectionStatus = "disconnected";
  const listeners = new Set<(status: ConnectionStatus) => void>();

  function setStatus(next: ConnectionStatus): void {
    if (status === next) return;
    status = next;
    for (const listener of [...listeners]) {
      if (status !== next) return;
      try {
        listener(next);
      } catch {
        /* Product observers cannot stop connection recovery. */
      }
    }
  }

  function retire(connection: Connection): void {
    if (current !== connection) return;
    current = undefined;
    const oldLegacy = legacy;
    legacy = undefined;
    oldLegacy?.close();
    try {
      reset?.(new ConnectionResetError());
    } catch {
      /* Other callers must still recover. */
    }
    connection.provider.dispose();
    if (!current) setStatus("disconnected");
    if (connection.verified && !stopped) setTimeout(activate, 0);
  }

  function open(): Connection {
    if (stopped) throw new ConnectionResetError();
    if (current) return current;
    let provider: WebSocketWireProvider;
    try {
      provider = createProvider(url);
    } catch (error) {
      setStatus("disconnected");
      throw error;
    }
    const connection = { provider, verified: false, checkedAt: 0 };
    current = connection;
    provider.subscribe((frame) => {
      if (current !== connection) return;
      connection.checkedAt = Date.now();
      if (legacy) {
        const decoded = decodeWireMessage(frame);
        if (decoded.isErr()) return retire(connection);
        if (!decoded.value.requestId.startsWith("host:"))
          return legacy.receive(frame);
      }
      receive?.(frame);
    });
    provider.subscribeClose?.(() => retire(connection));
    setStatus("connecting");
    return connection;
  }

  function ready(connection: Connection): Promise<void> {
    if (connection.verified && Date.now() - connection.checkedAt < 10_000)
      return Promise.resolve();
    return (connection.checking ??= Promise.resolve(handshake())
      .then((result) => {
        if (result.isErr() || current !== connection)
          throw new ConnectionResetError();
        connection.verified = true;
        connection.checkedAt = Date.now();
        setStatus("connected");
      })
      .catch((error) => {
        retire(connection);
        throw error;
      })
      .finally(() => {
        connection.checking = undefined;
      }));
  }

  function activate(): void {
    try {
      void ready(open()).catch(() => {});
    } catch {
      /* A later call can try again. */
    }
  }

  function stop(): void {
    stopped = true;
    if (current) retire(current);
  }

  const transport = createTransport(
    {
      postMessage(frame) {
        const connection = current;
        if (!connection) return;
        try {
          connection.provider.postMessage(frame);
        } catch {
          retire(connection);
        }
      },
      subscribe(callback) {
        receive = callback;
        return () => {
          receive = undefined;
        };
      },
      subscribeReset(callback) {
        reset = callback;
        return () => {
          reset = undefined;
        };
      },
      dispose: stop,
    },
    {
      requestIdPrefix: "host:",
      prepare(ids) {
        const connection = open();
        return ids.trait === SYSTEM_HANDSHAKE.trait &&
          ids.method === SYSTEM_HANDSHAKE.method
          ? connection.provider.opened
          : ready(connection);
      },
    },
  );
  const client = createClient(transport);
  const handshake = client.system.handshake.bind(client.system);

  return {
    get client() {
      activate();
      return client;
    },
    internal: createInternalClient(transport),
    get legacyPort() {
      if (legacyPort) return legacyPort;
      const { port1: product, port2: host } = new MessageChannel();
      legacyPort = product;
      const adapter = {
        receive(frame: Uint8Array) {
          host.postMessage(frame);
        },
        close() {
          host.close();
        },
      };
      legacy = adapter;
      const onMessage = (event: MessageEvent) => {
        if (legacy !== adapter || !current?.verified) return;
        const { data: frame } = event;
        if (!(frame instanceof Uint8Array)) return;
        const decoded = decodeWireMessage(frame);
        if (decoded.isErr() || decoded.value.requestId.startsWith("host:"))
          return;
        try {
          current.provider.postMessage(frame);
        } catch {
          if (current) retire(current);
        }
      };
      try {
        void ready(open()).then(
          () => {
            if (legacy !== adapter) return;
            host.addEventListener("message", onMessage);
            host.start();
          },
          () => adapter.close(),
        );
      } catch {
        adapter.close();
      }
      return product;
    },
    subscribeConnectionStatus(callback) {
      listeners.add(callback);
      callback(status);
      return () => {
        listeners.delete(callback);
      };
    },
    dispose() {
      try {
        stop();
      } finally {
        transport.dispose();
      }
    },
  };
}
