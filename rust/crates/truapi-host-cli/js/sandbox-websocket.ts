import type { WebSocketBackendFactory } from "../../../../js/container/src/websocket.ts";

const HostWebSocket = WebSocket as unknown as {
  new (url: string, options: Bun.WebSocketOptions): WebSocket;
};

export interface Authorization {
  result: Promise<boolean>;
  cancel(): void;
}

type SocketEvent =
  | { type: "open"; protocol: string; extensions: string }
  | { type: "message"; data: string | number[] }
  | { type: "error" }
  | { type: "close"; code: number; reason: string; wasClean: boolean };

interface Connection {
  socket?: WebSocket;
  authorization: Authorization;
  closed: boolean;
  events: SocketEvent[];
  receive?: (event: SocketEvent) => void;
}

export function createWebSocketBroker(
  authorize: (url: string) => Authorization,
  origin: string,
) {
  const connections = new Map<number, Connection>();
  let lastId = 0;
  let disposed = false;

  function publish(connection: Connection, event: SocketEvent): void {
    if (connection.receive) {
      const receive = connection.receive;
      connection.receive = undefined;
      receive(event);
    } else connection.events.push(event);
  }

  function finish(
    connection: Connection,
    code = 1006,
    reason = "",
    wasClean = false,
    failed = false,
  ): void {
    if (connection.closed) return;
    connection.closed = true;
    connection.authorization.cancel();
    if (failed) publish(connection, { type: "error" });
    publish(connection, { type: "close", code, reason, wasClean });
  }

  return {
    command(input: unknown): void | Promise<SocketEvent> {
      if (disposed || !input || typeof input !== "object")
        throw new Error("Invalid WebSocket command");
      const command = input as Record<string, unknown>;
      const id = command.id;
      if (typeof id !== "number" || !Number.isSafeInteger(id) || id <= 0)
        throw new Error("Invalid WebSocket ID");
      if (command.type === "connect") {
        if (id <= lastId || typeof command.url !== "string")
          throw new Error("Invalid WebSocket connection");
        const url = new URL(command.url);
        if (
          !["ws:", "wss:"].includes(url.protocol) ||
          url.hash ||
          !Array.isArray(command.protocols) ||
          command.protocols.some(
            (protocol: unknown) =>
              typeof protocol !== "string" ||
              !/^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/.test(protocol),
          ) ||
          new Set(command.protocols).size !== command.protocols.length
        )
          throw new Error("Invalid WebSocket destination or protocols");
        lastId = id;
        const protocols = command.protocols as string[];
        const authorization = authorize(url.href);
        const connection: Connection = {
          authorization,
          closed: false,
          events: [],
        };
        connections.set(id, connection);
        void authorization.result.then(
          (allowed) => {
            if (disposed || connection.closed) return;
            if (!allowed) return finish(connection, 1006, "", false, true);
            try {
              const socket = new HostWebSocket(url.href, {
                protocols,
                headers: { Origin: origin },
              });
              connection.socket = socket;
              socket.binaryType = "arraybuffer";
              socket.onopen = () => {
                if (!connection.closed)
                  publish(connection, {
                    type: "open",
                    protocol: socket.protocol,
                    extensions: socket.extensions,
                  });
              };
              socket.onmessage = (event) => {
                if (!connection.closed)
                  publish(connection, {
                    type: "message",
                    data:
                      typeof event.data === "string"
                        ? event.data
                        : Array.from(new Uint8Array(event.data)),
                  });
              };
              socket.onerror = () => {
                if (!connection.closed) publish(connection, { type: "error" });
              };
              socket.onclose = (event) =>
                finish(connection, event.code, event.reason, event.wasClean);
            } catch {
              finish(connection, 1006, "", false, true);
            }
          },
          () => finish(connection, 1006, "", false, true),
        );
        return;
      }
      const connection = connections.get(id);
      if (!connection) throw new Error("Unknown WebSocket connection");
      if (command.type === "poll") {
        if (connection.receive)
          throw new Error("WebSocket poll already pending");
        const next = connection.events.shift();
        const result = next
          ? Promise.resolve(next)
          : new Promise<SocketEvent>((resolve) => {
              connection.receive = resolve;
            });
        return result.then((event) => {
          if (event.type === "close") connections.delete(id);
          return event;
        });
      }
      if (command.type === "close") {
        const { code, reason } = command;
        if (
          (code !== undefined &&
            (typeof code !== "number" ||
              !Number.isInteger(code) ||
              (code !== 1000 && (code < 3000 || code > 4999)))) ||
          (reason !== undefined &&
            (typeof reason !== "string" ||
              new TextEncoder().encode(reason).length > 123))
        )
          throw new Error("Invalid WebSocket close");
        if (!connection.closed) {
          connection.authorization.cancel();
          if (connection.socket) connection.socket.close(code, reason);
          else finish(connection, 1006, "", false, true);
        }
        return;
      }
      if (command.type === "send") {
        const { data } = command;
        if (
          typeof data !== "string" &&
          !(
            Array.isArray(data) &&
            data.length <= 64 * 1024 * 1024 &&
            data.every(
              (byte: unknown) =>
                typeof byte === "number" &&
                Number.isInteger(byte) &&
                byte >= 0 &&
                byte <= 255,
            )
          )
        )
          throw new Error("Invalid WebSocket message");
        if (
          connection.closed ||
          connection.socket?.readyState !== WebSocket.OPEN
        )
          throw new Error("WebSocket is not open");
        connection.socket.send(
          typeof data === "string" ? data : Uint8Array.from(data),
        );
        return;
      }
      throw new Error("Invalid WebSocket command");
    },
    dispose(): void {
      disposed = true;
      for (const connection of connections.values()) {
        finish(connection);
        connection.socket?.close();
      }
      connections.clear();
    },
  };
}

export function installWebSocketBackend(): void {
  const bootstrap = window as unknown as {
    __truapi_websocket__?: (command: unknown) => Promise<SocketEvent | void>;
    __truapi_websocket_connect__?: WebSocketBackendFactory;
  };
  const command = bootstrap.__truapi_websocket__!;
  delete bootstrap.__truapi_websocket__;
  const NativeTarget = EventTarget;
  const NativeEvent = Event;
  const NativeMessage = MessageEvent;
  const NativeClose = CloseEvent;
  const NativeBlob = Blob;
  const NativeBytes = Uint8Array;
  const NativeEncoder = TextEncoder;
  const NativeError = DOMException;
  const NativeUrl = URL;
  const apply = Reflect.apply;
  const dispatch = EventTarget.prototype.dispatchEvent;
  const then = Promise.prototype.then;
  const resolve = Promise.resolve.bind(Promise);
  const from = Array.from;
  const blobBuffer = Blob.prototype.arrayBuffer;
  const blobSize = Object.getOwnPropertyDescriptor(
    Blob.prototype,
    "size",
  )!.get!;
  const bufferSize = Object.getOwnPropertyDescriptor(
    ArrayBuffer.prototype,
    "byteLength",
  )!.get!;
  const viewPrototype = Object.getPrototypeOf(Uint8Array.prototype);
  const viewBuffer = Object.getOwnPropertyDescriptor(
    viewPrototype,
    "buffer",
  )!.get!;
  const viewOffset = Object.getOwnPropertyDescriptor(
    viewPrototype,
    "byteOffset",
  )!.get!;
  const viewSize = Object.getOwnPropertyDescriptor(
    viewPrototype,
    "byteLength",
  )!.get!;
  const dataBuffer = Object.getOwnPropertyDescriptor(
    DataView.prototype,
    "buffer",
  )!.get!;
  const dataOffset = Object.getOwnPropertyDescriptor(
    DataView.prototype,
    "byteOffset",
  )!.get!;
  const dataSize = Object.getOwnPropertyDescriptor(
    DataView.prototype,
    "byteLength",
  )!.get!;
  const encode = TextEncoder.prototype.encode;
  const encoder = new NativeEncoder();
  let nextId = 0;

  bootstrap.__truapi_websocket_connect__ = (url, protocols) => {
    const target = new NativeTarget() as EventTarget & {
      url: string;
      readyState: number;
      bufferedAmount: number;
      protocol: string;
      extensions: string;
      binaryType: BinaryType;
      send(data: string | Blob | ArrayBuffer | ArrayBufferView): void;
      close(code?: number, reason?: string): void;
    };
    const id = ++nextId;
    target.url = url;
    target.readyState = 0;
    target.bufferedAmount = 0;
    target.protocol = "";
    target.extensions = "";
    target.binaryType = "blob";
    let sends: Promise<unknown> = resolve();
    let ended = false;

    function emit(event: Event): void {
      apply(dispatch, target, [event]);
    }
    function fail(): void {
      if (ended) return;
      ended = true;
      target.readyState = 3;
      emit(new NativeEvent("error"));
      emit(new NativeClose("close", { code: 1006, wasClean: false }));
      apply(then, command({ type: "close", id }), [undefined, () => {}]);
    }
    function poll(): void {
      if (ended) return;
      apply(then, command({ type: "poll", id }), [
        (event: SocketEvent) => {
          if (ended) return;
          switch (event.type) {
            case "open":
              if (target.readyState !== 0) break;
              target.readyState = 1;
              target.protocol = event.protocol;
              target.extensions = event.extensions;
              emit(new NativeEvent("open"));
              break;
            case "message": {
              if (target.readyState !== 1) break;
              const data =
                typeof event.data === "string"
                  ? event.data
                  : target.binaryType === "arraybuffer"
                    ? new NativeBytes(event.data).buffer
                    : new NativeBlob([new NativeBytes(event.data)]);
              emit(
                new NativeMessage("message", {
                  data,
                  origin: new NativeUrl(url).origin,
                }),
              );
              break;
            }
            case "error":
              emit(new NativeEvent("error"));
              break;
            case "close":
              ended = true;
              target.readyState = 3;
              emit(new NativeClose("close", event));
              return;
          }
          poll();
        },
        fail,
      ]);
    }
    target.send = (data) => {
      if (target.readyState === 0)
        throw new NativeError("WebSocket is connecting", "InvalidStateError");
      if (target.readyState !== 1) return;
      let payload: Promise<string | number[]>;
      let size: number;
      if (typeof data === "string") {
        size = apply(encode, encoder, [data]).length;
        payload = resolve(data);
      } else {
        try {
          size = apply(blobSize, data, []);
          payload = apply(then, apply(blobBuffer, data, []), [
            (buffer: ArrayBuffer) => from(new NativeBytes(buffer)),
          ]);
        } catch {
          let bytes: Uint8Array;
          try {
            bytes = new NativeBytes(
              data as ArrayBuffer,
              0,
              apply(bufferSize, data, []),
            );
          } catch {
            try {
              bytes = new NativeBytes(
                apply(viewBuffer, data, []),
                apply(viewOffset, data, []),
                apply(viewSize, data, []),
              );
            } catch {
              bytes = new NativeBytes(
                apply(dataBuffer, data, []),
                apply(dataOffset, data, []),
                apply(dataSize, data, []),
              );
            }
          }
          size = apply(viewSize, bytes, []);
          payload = resolve(from(bytes));
        }
      }
      target.bufferedAmount += size;
      sends = apply(then, sends, [
        () =>
          apply(then, payload, [
            (message: string | number[]) => {
              if (ended) return;
              return apply(then, command({ type: "send", id, data: message }), [
                () => {
                  target.bufferedAmount -= size;
                },
              ]);
            },
          ]),
      ]);
      apply(then, sends, [undefined, fail]);
    };
    target.close = (code, reason) => {
      if (target.readyState >= 2) return;
      target.readyState = 2;
      sends = apply(then, sends, [
        () => command({ type: "close", id, code, reason }),
      ]);
      apply(then, sends, [undefined, fail]);
    };
    apply(then, command({ type: "connect", id, url, protocols }), [poll, fail]);
    return target;
  };
}
