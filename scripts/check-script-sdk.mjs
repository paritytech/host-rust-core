#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const source = fileURLToPath(
  new URL("../rust/crates/truapi-host-cli/js/", import.meta.url),
);
const tools = fileURLToPath(new URL("../.agent/tools/", import.meta.url));
await mkdir(tools, { recursive: true });
const workspace = await mkdtemp(join(tools, "script-sdk-check-"));
const directory = join(workspace, "project");
await mkdir(directory);
const manifest = JSON.parse(
  await readFile(join(source, "script-package.json"), "utf8"),
);
const sdk = manifest.dependencies["@parity/product-sdk"];

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
    "--no-cache",
  ]);
  bun(["run", "typecheck"]);
  bun([
    "--eval",
    'import { bindHost } from "@parity/product-sdk/host"; if (typeof bindHost !== "function") throw new Error("Product SDK does not export bindHost");',
  ]);
  console.log("Default script dependencies, types, and SDK binding passed.");
} catch (error) {
  console.error(error.message);
  console.error(
    `CLI release blocked: the default script project requires a published, compatible Product SDK ${sdk} with bindHost. Verify dependency availability and compatibility before publishing the CLI.`,
  );
  process.exitCode = 1;
} finally {
  console.log(`Script project retained at ${directory}`);
}
