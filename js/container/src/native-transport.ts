// =============================================================================
// Platform-agnostic request/response RPC over an opaque native channel.
//
// One request, one reply — no streaming. The outbound side serializes a
// request envelope and hands it to `sendToNative`; the inbound side is driven
// by `dispatch`, which the platform layer wires to the native reply callback.
// Request ids are 128-bit random hex so a caller sharing this realm cannot
// guess a pending id and forge a reply. The RNG and the JSON (de)serializer on
// the id's path are captured at init, so a product cannot make ids predictable
// or read an outbound id by overriding the globals later.
// =============================================================================

/** Sends a serialized request envelope to the native side. */
export type NativeSender = (message: string) => void;

/** A request/response channel to the native host. */
export interface NativeTransport {
  /** Sends a request and resolves with the native `value` (or rejects on error). */
  callNative(method: string, params: unknown): Promise<unknown>;
  /**
   * Routes a native reply to its pending request. The payload may be a JSON
   * string or an already-parsed object (some hosts invoke the reply callback
   * with an object literal). Unknown or stale ids are ignored so a forged or
   * late reply cannot disturb other calls.
   */
  dispatch(id: string, payload: string | object): void;
}

interface PendingCall {
  resolve: (value: unknown) => void;
  reject: (error: unknown) => void;
}

// Capture the primitives on the id's path at init (documentStart), before any
// product script runs — the same discipline the platform bridges apply to the
// native sender. A product that later overrides `crypto.getRandomValues`,
// `Uint8Array`, or `JSON.stringify` cannot make request ids predictable or
// observe an outbound id.
const getRandomValues = crypto.getRandomValues.bind(crypto);
const TypedArray = Uint8Array;
const stringify = JSON.stringify;
const parse = JSON.parse;
const HEX = '0123456789abcdef';

/** 128-bit random hex id; unguessable so replies cannot be forged by id. */
function randomId(): string {
  const bytes = new TypedArray(16);
  getRandomValues(bytes);
  // Encode without Number.prototype.toString / String.prototype.padStart or the
  // typed-array iterator — all poisonable. Integer indexing, bit ops, and string
  // concat are primitive operations a product cannot override.
  let hex = '';
  for (let i = 0; i < 16; i++) {
    const b = bytes[i];
    hex += HEX[b >> 4] + HEX[b & 15];
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
      sendToNative(stringify({ type: 'request', id, method, params }));
    });
  }

  function dispatch(id: string, payload: string | object): void {
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
      reply = typeof payload === 'string' ? parse(payload) : payload;
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
