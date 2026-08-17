#!/usr/bin/env node
// Fail the dotli bootstrap early when the built WASM is too large for dotli's
// service worker to precache.
//
// vite-plugin-pwa throws on an oversized precache entry rather than warning, so
// an over-limit WASM makes `make dev` and `make e2e-dotli` fail deep inside a
// dotli build with a message that does not name the cause. This runs during
// dev-link-check instead, before anything starts.
//
// The limit is read out of dotli's own vite config rather than restated here,
// so bumping the submodule cannot leave a stale copy behind. Anything it cannot
// parse is a warning, not a failure: a dotli refactor should not break this
// checkout's bootstrap over a convenience check.
//
// Usage: node scripts/check-dotli-wasm-precache.mjs <wasm> <vite-config>

import { readFileSync, statSync } from "node:fs";

const [wasmPath, configPath] = process.argv.slice(2);

if (!wasmPath || !configPath) {
  console.error("usage: check-dotli-wasm-precache.mjs <wasm> <vite-config>");
  process.exit(2);
}

function skip(reason) {
  console.warn(`skipping the WASM precache check: ${reason}`);
  process.exit(0);
}

/** Evaluate a `32 * 1024 * 1024` style product, or null if it is anything else. */
function evaluateProduct(expression) {
  const factors = expression.split("*").map((factor) => Number(factor.trim()));
  if (factors.some((factor) => !Number.isSafeInteger(factor) || factor <= 0)) {
    return null;
  }
  return factors.reduce((product, factor) => product * factor, 1);
}

let config;
try {
  config = readFileSync(configPath, "utf8");
} catch (err) {
  skip(`cannot read ${configPath} (${err.code ?? err.message})`);
}

// Take the largest parseable value rather than the first. A commented-out or
// superseded line would otherwise substitute a smaller limit and fail the build
// for a size dotli actually accepts.
const limits = [...config.matchAll(/maximumFileSizeToCacheInBytes:\s*([^,;\n]+)/g)]
  .map((match) => evaluateProduct(match[1]))
  .filter((limit) => limit !== null);

if (limits.length === 0) {
  skip(`no usable maximumFileSizeToCacheInBytes in ${configPath}`);
}

const limit = Math.max(...limits);
const size = statSync(wasmPath).size;

if (size > limit) {
  console.error(
    `${wasmPath} is ${size} bytes, over the ${limit}-byte precache limit dotli sets.`,
  );
  console.error("dotli's build fails on this, so the preview cannot start.");
  console.error(
    "The dev WASM profile is far past the limit and cannot be used with the",
  );
  console.error(
    "dotli preview. Rebuild at the default profile: TRUAPI_WASM_PROFILE=release make wasm",
  );
  process.exit(1);
}
