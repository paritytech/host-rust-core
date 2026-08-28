import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { run } from "./truapi-host-release.mjs";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const stageScript = join(
  repoRoot,
  "ios/truapi-provider/scripts/stage-xcframework.sh",
);

/**
 * The slices rebuild.sh produces for a full build. The staging script matches
 * on the layout rather than on these names, so a third slice needs no change
 * here, but two is enough to prove the strip reaches every slice.
 */
const slices = ["ios-arm64", "ios-arm64-simulator"];

/**
 * Write a directory shaped like the xcframework rebuild.sh hands to staging:
 * one Headers folder per slice, each carrying the generated header and the
 * modulemap that collides with a consumer's own UniFFI framework.
 */
function writeXcframework(root) {
  mkdirSync(root, { recursive: true });
  writeFileSync(join(root, "Info.plist"), "<plist></plist>\n");
  for (const slice of slices) {
    const headers = join(root, slice, "Headers");
    mkdirSync(headers, { recursive: true });
    writeFileSync(join(root, slice, "libtruapi_provider.a"), "");
    writeFileSync(join(headers, "truapi_providerFFI.h"), "// generated\n");
    writeFileSync(
      join(headers, "module.modulemap"),
      'module truapi_providerFFI {\n    header "truapi_providerFFI.h"\n}\n',
    );
  }
}

/**
 * Stage a fresh fixture in a temp workspace and hand the result to `body`.
 * PACKAGE_ROOT and SOURCE are the two overrides the script reads, so nothing
 * here touches the checkout.
 */
async function withStaging(body, { writeSource = true } = {}) {
  const workspace = mkdtempSync(join(tmpdir(), "truapi-provider-staging-"));
  try {
    const source = join(workspace, "target/truapi_provider.xcframework");
    const packageRoot = join(workspace, "package");
    if (writeSource) writeXcframework(source);
    mkdirSync(packageRoot, { recursive: true });

    const result = await run("sh", [stageScript], {
      env: { ...process.env, PACKAGE_ROOT: packageRoot, SOURCE: source },
    });

    await body({
      result,
      staged: join(packageRoot, "Binaries/truapi_provider.xcframework"),
    });
  } finally {
    rmSync(workspace, { recursive: true, force: true });
  }
}

test("staging strips every per-slice modulemap", async () => {
  await withStaging(({ result, staged }) => {
    assert.equal(result.status, 0, result.stderr);

    const entries = readdirSync(staged, { recursive: true });
    assert.deepEqual(
      entries.filter((entry) => entry.endsWith("module.modulemap")),
      [],
      "a slice-local modulemap collides with the consumer's own",
    );
  });
});

test("staging keeps the headers and the rest of the tree", async () => {
  await withStaging(({ result, staged }) => {
    assert.equal(result.status, 0, result.stderr);

    const entries = readdirSync(staged, { recursive: true });
    assert.ok(entries.includes("Info.plist"), "Info.plist survives");
    for (const slice of slices) {
      assert.ok(
        entries.includes(join(slice, "Headers/truapi_providerFFI.h")),
        `${slice} keeps its generated header`,
      );
      assert.ok(
        entries.includes(join(slice, "libtruapi_provider.a")),
        `${slice} keeps its library`,
      );
    }
  });
});

test("staging refuses when the framework has not been built", async () => {
  await withStaging(
    ({ result }) => {
      assert.equal(result.status, 66, result.stderr);
      assert.match(result.stderr, /rebuild\.sh/);
    },
    { writeSource: false },
  );
});
