import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// The worker names the wasm glue in a literal import so bundlers resolve it
// statically and emit it alongside `truapi_server_bg.wasm`. Hidden behind a
// variable or `@vite-ignore` the import leaves the module graph, every bundler
// silently omits both files, and the failure only surfaces when a host's worker
// tries to instantiate the core. These assertions run against the compiled
// output because that is what a consuming bundler reads.

const packageRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const workerEntry = join(packageRoot, "dist/worker-runtime.js");
const GLUE_SPECIFIER = "./wasm/web/truapi_server.js";

describe("worker wasm import", () => {
  it("names the glue in a statically analysable import", () => {
    expect(
      existsSync(workerEntry),
      `${workerEntry} is missing; run \`npm run build\` first`,
    ).toBe(true);
    const compiled = readFileSync(workerEntry, "utf8");

    expect(compiled).toContain(`import("${GLUE_SPECIFIER}")`);
    expect(compiled).not.toContain("@vite-ignore");
  });

  it("resolves that specifier against the built bundle", () => {
    const glue = join(packageRoot, "dist", GLUE_SPECIFIER);
    if (!existsSync(glue)) {
      // `make wasm` is a local step; CI typechecks without the artifact.
      return;
    }

    expect(readFileSync(glue, "utf8")).toContain("truapi_server_bg.wasm");
  });
});
