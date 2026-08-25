/**
 * Browser bridge to a local `truapi-host` CLI — a real host on the desk
 * instead of the phone, so hosted-mode code paths run in a plain browser tab.
 *
 * The CLI serves product frames as one binary WebSocket message per SCALE
 * protocol frame. `@parity/truapi`'s sandbox bootstrap speaks exactly that
 * frame format, but only over two browser transports: the iframe
 * `truapi-init` handover, and a `MessagePort` parked on
 * `window.__HOST_API_PORT__`. This supplies the missing pipe: a
 * `MessageChannel` whose far end is pumped into the CLI's socket. The SDK
 * then detects a container and talks to the CLI without knowing anything
 * changed (`isCorrectEnvironment` returns true as soon as
 * `__HOST_API_PORT__` is set, and it polls for up to 20s, so connecting
 * after page load is fine).
 *
 * Production hosts embed the runtime in-process and never dial a WebSocket,
 * which is why this transport lives in the dev package and not in
 * `@parity/truapi`.
 *
 * Dev-only by construction: call it with the URL from a dev-only injected
 * environment variable, and production builds — where the variable is unset —
 * return before touching anything.
 */

declare global {
  interface Window {
    /** MessagePort the truapi sandbox adopts as its host transport. */
    __HOST_API_PORT__?: MessagePort;
  }
}

export type CliHostBridgeStatus = "connecting" | "connected" | "disconnected";

export interface ConnectCliHostOptions {
  /**
   * Frame WebSocket endpoint of the local host, e.g. `ws://127.0.0.1:9955`.
   * The `truapi-dev-host` launcher injects it as `TRUAPI_HOST_WS` with
   * `NEXT_PUBLIC_` and `VITE_` prefixed copies; pass the one your framework
   * exposes. `undefined` disarms the bridge, which is what makes it erasable
   * from production builds.
   */
  url: string | undefined;
  onStatus?: (status: CliHostBridgeStatus) => void;
}

/**
 * Arm the CLI host bridge. Returns a no-op cleanup: the SDK owns the
 * MessagePort for the page lifetime, so the singleton socket deliberately
 * survives caller re-runs (React development-mode effect replays included).
 */
export function connectCliHost({
  url,
  onStatus,
}: ConnectCliHostOptions): () => void {
  if (!url || typeof window === "undefined") return () => {};
  if (window.__HOST_API_PORT__) {
    onStatus?.("connected");
    return () => {};
  }

  onStatus?.("connecting");
  const ws = new WebSocket(url);
  ws.binaryType = "arraybuffer";
  const { port1, port2 } = new MessageChannel();
  // Frames the app produces before the socket is open. The SDK queues nothing
  // on its side once it has a port, so the queue has to live here.
  const pending: Uint8Array[] = [];

  port2.onmessage = (event: MessageEvent<Uint8Array>) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(event.data);
    else pending.push(event.data);
  };
  port2.start();

  ws.onopen = () => {
    onStatus?.("connected");
    console.info(`[cli-host] connected to ${url}`);
    for (const frame of pending.splice(0)) ws.send(frame);
  };
  // The SDK's provider only accepts `Uint8Array`, never a bare ArrayBuffer.
  ws.onmessage = (event: MessageEvent<ArrayBuffer>) => {
    port2.postMessage(new Uint8Array(event.data));
  };
  ws.onclose = () => {
    onStatus?.("disconnected");
    // Nothing to signal down a MessagePort — every pending host call just
    // stops resolving, which looks like a hung app. Say so loudly instead.
    console.warn(
      `[cli-host] socket to ${url} closed — reload after restarting the host`,
    );
  };
  ws.onerror = () => {
    onStatus?.("disconnected");
    console.error(
      `[cli-host] cannot reach ${url} — is \`truapi-host\` running?`,
    );
  };

  window.__HOST_API_PORT__ = port1;
  console.info(`[cli-host] host bridge armed for ${url}`);
  return () => {};
}
