#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const source = fileURLToPath(
  new URL("../rust/crates/truapi-host-cli/js/", import.meta.url),
);
const manifest = JSON.parse(
  await readFile(join(source, "script-package.json"), "utf8"),
);
const sdk = manifest.dependencies["@parity/product-sdk"];
const { version } = JSON.parse(
  await readFile(
    new URL("../js/packages/truapi/package.json", import.meta.url),
    "utf8",
  ),
);
const tools = fileURLToPath(new URL("../.agent/tools/", import.meta.url));
await mkdir(tools, { recursive: true });
const workspace = await mkdtemp(join(tools, "script-sdk-check-"));
const directory = join(workspace, "project");

function bun(args) {
  const result = spawnSync("bun", args, {
    cwd: directory,
    stdio: "inherit",
    timeout: 120000,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `bun ${args[0]} failed (${result.status ?? result.signal})`,
    );
  }
}

try {
  if (manifest.overrides?.["@parity/truapi"] !== version) {
    throw new Error(
      `Script TrUAPI override must match the host version ${version}; run npm run sync-release-versions.`,
    );
  }
  await mkdir(directory);
  for (const [template, filename] of [
    ["script-package.json", "package.json"],
    ["sdk-script.ts", "script.ts"],
    ["script-tsconfig.json", "tsconfig.json"],
    ["script-types.d.ts", "script.types.d.ts"],
  ]) {
    await copyFile(join(source, template), join(directory, filename));
  }
  console.log(`Checking the default script project with Product SDK ${sdk}`);
  bun([
    "install",
    "--registry=https://registry.npmjs.org",
    `--cache-dir=${join(workspace, "cache")}`,
  ]);
  bun(["run", "typecheck"]);
  bun([
    "--eval",
    'import { createApp } from "@parity/product-sdk"; if (typeof createApp !== "function") throw new Error("Product SDK does not export createApp");',
  ]);
  console.log("Default script dependencies, types, and SDK exports passed.");
} catch (error) {
  console.error(error.message);
  console.error(
    `CLI release blocked: the default script project requires a published, compatible Product SDK ${sdk}. Verify dependency availability and compatibility before publishing the CLI.`,
  );
  process.exitCode = 1;
} finally {
  await rm(workspace, { recursive: true, force: true });
}
