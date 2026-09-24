// The browser core does not link `verifiable`: it fetches the module from
// `verifiable/` beside itself and checks it against the hash `make wasm`
// compiled in. A wrong path or a stale copy still builds and loads, and fails
// only on the first ring-VRF call, which no product call reaches here without a
// chain. So this drives the core's own load through its test-host export.
import { describe, expect, it } from "bun:test";
import { pathToFileURL } from "node:url";

import { wasmArtifact, wasmIsBuilt } from "./require-wasm.js";

const suite = wasmIsBuilt(
  "testing/truapi_server.js",
  "testing/verifiable/truapi_verifiable.js",
)
  ? describe
  : describe.skip;

async function glue<T>(
  relativePath: string,
): Promise<T & { default(): Promise<unknown> }> {
  const module = (await import(
    pathToFileURL(wasmArtifact(relativePath)).href
  )) as T & { default(): Promise<unknown> };
  await module.default();
  return module;
}

suite("verifiable module", () => {
  it("loads beside the testing core and derives the member it derives directly", async () => {
    const core = await glue<{
      ringVrfMember(entropy: Uint8Array): Promise<Uint8Array>;
    }>("testing/truapi_server.js");
    const verifiable = await glue<{ member(entropy: Uint8Array): Uint8Array }>(
      "testing/verifiable/truapi_verifiable.js",
    );
    const entropy = new Uint8Array(32).fill(4);

    // `member` answers a SCALE `Result<[u8; 32], String>`: `0x00`, then the key.
    const direct = verifiable.member(entropy);
    expect(direct[0]).toBe(0);
    expect(await core.ringVrfMember(entropy)).toEqual(direct.subarray(1));
  });
});
