import { pathToFileURL } from "node:url";
import { inspect } from "node:util";
import {
  createClient,
  createTransport,
  type ProductAccountId,
  type TrUApiClient,
} from "../../../../js/packages/truapi/src/index.ts";
import { createCliAuthorization } from "./permissions.ts";
import { installFetchGate } from "../../../../js/container/src/network.ts";
import { installWebSocketGate } from "../../../../js/container/src/websocket.ts";
import { installXhrGate } from "../../../../js/container/src/xhr.ts";
import { reportLockdownFailures } from "../../../../js/container/src/freeze.ts";
import { wsProvider } from "./ws-provider.ts";

/// The host context injected alongside `truapi`. It only exposes what a script
/// can't get from `truapi` alone: the product id the host serves, so product
/// accounts stay in sync with `--product-id` (hardcoding a mismatched id fails
/// signing with `PermissionDenied`). Use `console.log` / `throw` for the rest.
export interface HostContext {
  /** The product id this host serves (its `--product-id`). */
  productId: string;
  /** A product account id for `derivationIndex` (default 0) under this product. */
  productAccount(index?: number): ProductAccountId;
}

declare global {
  // eslint-disable-next-line no-var
  var truapi: TrUApiClient;
  // eslint-disable-next-line no-var
  var host: HostContext;
  // Playground examples receive this helper from `runExample`; expose the
  // same contract to directly imported CLI scripts.
  // eslint-disable-next-line no-var
  var assert: (condition: unknown, ...message: unknown[]) => asserts condition;
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} must be set`);
  return value;
}

async function main() {
  const frameUrl = requireEnv("TRUAPI_FRAME_URL");
  const productId = requireEnv("TRUAPI_PRODUCT_ID");
  const scriptPath = requireEnv("TRUAPI_SCRIPT");
  const provider = wsProvider(frameUrl);
  const context: HostContext = {
    productId,
    productAccount: (index = 0) => ({
      dotNsIdentifier: productId,
      derivationIndex: { tag: "Index", value: index },
    }),
  };
  const transport = createTransport(provider);
  globalThis.truapi = createClient(transport);
  globalThis.host = context;
  globalThis.assert = (condition: unknown, ...message: unknown[]) => {
    if (condition) return;
    const detail = message
      .map((value) =>
        typeof value === "string"
          ? value
          : inspect(value, { colors: false, depth: 5 }),
      )
      .join(" ");
    throw new Error(detail || "assertion failed");
  };

  const authorization = createCliAuthorization(transport);
  installFetchGate(globalThis, authorization.network);
  installWebSocketGate(globalThis, authorization.network);
  installXhrGate(globalThis, authorization.network);
  reportLockdownFailures();

  const timer = setTimeout(() => {
    console.error(`[runner] timed out connecting to ${frameUrl}`);
    process.exit(2);
  }, 15_000);
  try {
    await provider.opened;
    clearTimeout(timer);
    if (process.env.TRUAPI_SCRIPT_CWD)
      process.chdir(process.env.TRUAPI_SCRIPT_CWD);
    const module = await import(pathToFileURL(scriptPath).href);
    if (typeof module.default === "function") await module.default(context);
  } finally {
    clearTimeout(timer);
    transport.dispose();
    provider.dispose();
  }
}

main().then(
  () => process.exit(0),
  (error) => {
    const message = String(error);
    const stack = error instanceof Error ? error.stack : undefined;
    const detail = stack?.includes(message)
      ? stack
      : `${message}${stack ? `\n${stack}` : ""}`;
    console.error(`[script error] ${detail}`);
    process.exit(1);
  },
);
