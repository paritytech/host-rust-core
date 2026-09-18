// The testing WASM bundle exists to carry a signing host: dev accounts sign
// locally instead of waiting on a wallet that is not there. That depends on a
// build flag (`--features wasm-signing-host` in `scripts/build-wasm.mjs`),
// and a flag is exactly the kind of thing that gets dropped in a refactor
// without anything failing — the bundle would still build, still load, and
// simply have no signing host in it.
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { wasmIsBuilt } from "./require-wasm.js";

const testingGlue = fileURLToPath(
  new URL("../../dist/wasm/testing/truapi_server.d.ts", import.meta.url),
);
const webGlue = fileURLToPath(
  new URL("../../dist/wasm/web/truapi_server.d.ts", import.meta.url),
);

const suite = wasmIsBuilt(
  "testing/truapi_server.d.ts",
  "web/truapi_server.d.ts",
)
  ? describe
  : describe.skip;

suite("testing wasm bundle", () => {
  it("carries a signing host", () => {
    expect(readFileSync(testingGlue, "utf8")).toContain(
      "export class WasmSigningHostRuntime",
    );
  });

  it("is the only bundle that does", () => {
    // The production browser host pairs with a wallet and must not ship a
    // key-holding runtime; that separation is the reason for two bundles.
    expect(readFileSync(webGlue, "utf8")).not.toContain(
      "export class WasmSigningHostRuntime",
    );
  });

  it("is the only bundle that can answer allocation as granted", () => {
    // `setGrantAllowancesUnchecked` hands a product a grant nothing allocated.
    // It is gated on the non-default `test-host` Cargo feature, which only
    // `scripts/build-wasm.mjs` turns on and only for this bundle, so a shipping
    // host has no entry point to it at all.
    expect(readFileSync(testingGlue, "utf8")).toContain(
      "setGrantAllowancesUnchecked",
    );
    expect(readFileSync(webGlue, "utf8")).not.toContain(
      "setGrantAllowancesUnchecked",
    );
  });
});
