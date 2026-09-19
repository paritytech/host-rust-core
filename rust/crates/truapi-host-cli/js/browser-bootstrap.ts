import {
  createClient,
  createMessagePortProvider,
  createTransport,
} from "@parity/truapi";
import type { HostContext } from "./runner.ts";

const runtime = globalThis as typeof globalThis & {
  __HOST_API_PORT__: MessagePort;
  __truapi_product_id__: string;
  __truapi_complete__: (error: string | null) => Promise<void>;
};

const complete = runtime.__truapi_complete__;
Reflect.deleteProperty(runtime, "__truapi_complete__");
const productId = runtime.__truapi_product_id__;
Reflect.deleteProperty(runtime, "__truapi_product_id__");
runtime.truapi = createClient(
  createTransport(createMessagePortProvider(runtime.__HOST_API_PORT__)),
);
runtime.host = Object.freeze<HostContext>({
  productId,
  productAccount: (index = 0) => ({
    dotNsIdentifier: productId,
    derivationIndex: { tag: "Index", value: index },
  }),
});
runtime.assert = (condition, ...message) => {
  if (!condition)
    throw new Error(message.map(String).join(" ") || "assertion failed");
};

try {
  const productURL = new URL("./product.mjs", import.meta.url).href;
  const product = await import(productURL);
  if (typeof product.default === "function")
    await product.default(runtime.host);
  await complete(null);
} catch (error) {
  await complete(
    error instanceof Error ? (error.stack ?? error.message) : String(error),
  );
}
