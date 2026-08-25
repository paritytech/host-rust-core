import {
  createClient,
  createTransport,
  type TrUApiClient,
  type WireProvider,
} from "@parity/truapi";
import { ss58Encode } from "./ss58.js";

/** Resolve `promise`, or `undefined` if it takes longer than `ms`. */
export function withTimeout<T>(
  promise: PromiseLike<T>,
  ms: number,
): Promise<T | undefined> {
  return Promise.race([
    Promise.resolve(promise),
    new Promise<undefined>((r) => setTimeout(() => r(undefined), ms)),
  ]);
}

/** Await a truapi call, `undefined` if the transport threw. The client hands
 * back a neverthrow `ResultAsync`: awaitable, but not a Promise, so it has no
 * `.catch` of its own. */
export async function attempt<T>(call: PromiseLike<T>): Promise<T | undefined> {
  try {
    return await call;
  } catch {
    return undefined;
  }
}

export interface HostConnection {
  client: TrUApiClient;
  close: () => void;
}

/**
 * A truapi client over the CLI's frame socket — the node-side twin of the
 * browser bridge. One binary WebSocket message per SCALE frame, which is the
 * wire both ends already speak, so this is a pipe and nothing more. Frames
 * posted before the socket opens are queued and flushed on open. (`@parity/
 * truapi` grows a `createWebSocketProvider` in 0.10.0; adopt it on the next
 * wire bump and delete this.)
 */
export function connectHost(wsUrl: string): HostConnection {
  const ws = new WebSocket(wsUrl);
  ws.binaryType = "arraybuffer";
  const listeners = new Set<(message: Uint8Array) => void>();
  const closeListeners = new Set<(error: Error) => void>();
  const pending: Uint8Array[] = [];
  let open = false;

  ws.addEventListener("open", () => {
    open = true;
    for (const frame of pending.splice(0)) ws.send(frame);
  });
  ws.addEventListener("message", (event) => {
    const bytes = new Uint8Array(event.data as ArrayBuffer);
    for (const listener of listeners) listener(bytes);
  });
  ws.addEventListener("close", () => {
    for (const listener of closeListeners) listener(new Error("socket closed"));
  });

  const provider: WireProvider = {
    postMessage: (frame) => (open ? ws.send(frame) : void pending.push(frame)),
    subscribe: (cb) => (listeners.add(cb), () => listeners.delete(cb)),
    subscribeClose: (cb) => (
      closeListeners.add(cb),
      () => closeListeners.delete(cb)
    ),
    dispose: () => ws.close(),
  };
  const client = createClient(createTransport(provider));
  return { client, close: () => ws.close() };
}

/**
 * Block until the host answers a real call, and return the signer's username.
 *
 * `--serve` prints its ready line once the signer exists, but attaching to
 * someone else's host gives us no such signal, and an open port is not
 * readiness — `getUserId` returning a username is. On a first run the CLI
 * provisions a lite username through the identity backend and registers the
 * statement-store allowance on-chain, which can take minutes.
 */
export async function waitForSigner(
  ws: string,
  log?: (line: string) => void,
): Promise<string> {
  let told = false;
  for (;;) {
    const { client, close } = connectHost(ws);
    const result = await withTimeout(
      attempt(client.account.getUserId()),
      10_000,
    );
    close();
    if (result?.isOk()) return result.value.primaryUsername;
    if (!told) {
      log?.(
        "host is up, waiting for its signer (first run provisions on-chain)",
      );
      told = true;
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
}

export interface PreflightOptions {
  /**
   * Probe the host with a throwaway signature. Only needed for an attached
   * host, whose configured product id is otherwise opaque: `getAccount`
   * succeeds for *any* product, so only a signing attempt distinguishes
   * "this host is ours" from "this host will refuse every signature later".
   * A host we just spawned received the id on argv, so skip the probe — it
   * would create a distracting automatic approval before the demo begins.
   */
  verifySigning?: boolean;
  log?: (line: string) => void;
}

/**
 * Report the product account the app will play as, and check that this host
 * really serves `productId`. Returns false when the host cannot serve it.
 */
export async function preflightProductAccount(
  ws: string,
  productId: string,
  { verifySigning = false, log }: PreflightOptions = {},
): Promise<boolean> {
  const { client, close } = connectHost(ws);
  const account = {
    dotNsIdentifier: productId,
    derivationIndex: { tag: "Index", value: 0 } as const,
  };
  try {
    const got = await client.account.getAccount({ productAccountId: account });
    if (got.isErr()) {
      log?.(
        `product account unavailable: ${JSON.stringify(got.error)}. A MalformedFrame naming ` +
          "`ProductAccountId::derivation_index` is a SCALE wire-version mismatch: this " +
          "package's `@parity/truapi` and the host binary must come from matching releases.",
      );
      return false;
    }
    log?.(
      `product account ${productId} (index 0): ${ss58Encode(got.value.account.publicKey)}`,
    );

    if (!verifySigning) return true;

    // Signs 0xdeadbeef and throws the signature away. On a host without
    // --auto-accept this raises a confirmation, so never block on it.
    const signed = await withTimeout(
      attempt(
        client.signing.signRaw({
          account,
          payload: { tag: "Bytes", value: { bytes: "0xdeadbeef" } },
        }),
      ),
      5000,
    );
    if (signed === undefined) {
      log?.("signing probe still pending — approve it in the host transcript");
    } else if (signed.isErr()) {
      log?.(
        `this host refuses to sign for ${productId}, so it is serving a ` +
          `different product id. Stop it and restart with --product-id ${productId}.`,
      );
      return false;
    }
    return true;
  } finally {
    close();
  }
}
