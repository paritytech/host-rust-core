import { pathToFileURL } from "node:url";
import { inspect } from "node:util";
import {
  createClient,
  createTransport,
} from "../../../../js/packages/truapi/src/index.ts";
import type { HostContext } from "./runner.ts";
import { wsProvider } from "./ws-provider.ts";

export async function runTrustedScript(
  frameUrl: string,
  productId: string,
  scriptPath: string,
): Promise<void> {
  const provider = wsProvider(frameUrl);
  const client = createClient(createTransport(provider));
  const context: HostContext = {
    productId,
    productAccount: (index = 0) => ({
      dotNsIdentifier: productId,
      derivationIndex: { tag: "Index", value: index },
    }),
  };
  globalThis.truapi = client;
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
  const timer = setTimeout(() => {
    console.error(`[runner] timed out connecting to ${frameUrl}`);
    process.exit(2);
  }, 15_000);
  try {
    await provider.opened;
    clearTimeout(timer);
    const module = await import(pathToFileURL(scriptPath).href);
    if (typeof module.default === "function") await module.default(context);
  } finally {
    clearTimeout(timer);
    provider.dispose();
  }
}
