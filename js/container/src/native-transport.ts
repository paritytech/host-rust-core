// =============================================================================
// Platform-agnostic request/response RPC over an opaque native channel.
//
// One request, one reply — no streaming. The outbound side serializes a
// request envelope and hands it to `sendToNative`; the inbound side is driven
// by `dispatch`, which the platform layer wires to the native reply callback.
// Request ids are 128-bit random hex so a caller sharing this realm cannot
// guess a pending id and forge a reply.
// =============================================================================

/** Sends a serialized request envelope to the native side. */
export type NativeSender = (message: string) => void;

/** A request/response channel to the native host. */
export interface NativeTransport {
  /** Sends a request and resolves with the native `value` (or rejects on error). */
  callNative(method: string, params: unknown): Promise<unknown>;
  /**
   * Routes a native reply to its pending request. Unknown or stale ids are
   * ignored so a forged or late reply cannot disturb other calls.
   */
  dispatch(id: string, payloadJson: string): void;
}

interface PendingCall {
  resolve: (value: unknown) => void;
  reject: (error: unknown) => void;
}

/** 128-bit random hex id; unguessable so replies cannot be forged by id. */
function randomId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let hex = '';
  for (const byte of bytes) {
    hex += byte.toString(16).padStart(2, '0');
  }
  return hex;
}

/** Builds a request/response transport over `sendToNative`. */
export function createNativeTransport(
  sendToNative: NativeSender,
): NativeTransport {
  const pending = new Map<string, PendingCall>();

  function callNative(method: string, params: unknown): Promise<unknown> {
    const id = randomId();
    return new Promise<unknown>((resolve, reject) => {
      pending.set(id, { resolve, reject });
      sendToNative(JSON.stringify({ type: 'request', id, method, params }));
    });
  }

  function dispatch(id: string, payloadJson: string): void {
    const entry = pending.get(id);
    if (entry === undefined) {
      return;
    }
    pending.delete(id);

    let reply: {
      value?: unknown;
      error?: { code?: string; message?: string } | string;
    };
    try {
      reply = JSON.parse(payloadJson);
    } catch {
      entry.reject(new Error('Malformed native reply'));
      return;
    }

    if (reply.error !== undefined && reply.error !== null) {
      const error = reply.error;
      const code = typeof error === 'string' ? error : error.code ?? 'native_error';
      const message = typeof error === 'string' ? error : error.message ?? code;
      entry.reject(Object.assign(new Error(message), { code }));
      return;
    }

    entry.resolve(reply.value);
  }

  return { callNative, dispatch };
}
