import { cp, mkdir, mkdtemp, readFile, rename, rm } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { buildBrowserAssets } from "../rust/crates/truapi-host-cli/js/browser-assets.ts";

const repository = resolve(import.meta.dir, "..");
const destination = resolve(process.argv[2] ?? join(repository, "target/dist"));
const require = createRequire(import.meta.url);
const dependencies = (await Bun.file(join(repository, "package.json")).json())
  .devDependencies;
const packages = new Map<string, string>();
for (const name of ["playwright-core", "esbuild-wasm"]) {
  const directory = dirname(require.resolve(`${name}/package.json`));
  const manifest = JSON.parse(
    await readFile(join(directory, "package.json"), "utf8"),
  );
  if (manifest.version !== dependencies[name]) {
    throw new Error(
      `Expected ${name} ${dependencies[name]}, found ${manifest.version}; run npm ci --ignore-scripts`,
    );
  }
  packages.set(name, directory);
}

await mkdir(destination, { recursive: true });
const staging = await mkdtemp(join(destination, ".runner-"));
try {
  const runner = await Bun.build({
    entrypoints: [join(repository, "rust/crates/truapi-host-cli/js/runner.ts")],
    target: "bun",
    format: "esm",
    external: ["playwright-core", "esbuild-wasm"],
    env: "disable",
  });
  if (!runner.success || runner.outputs.length !== 1) {
    throw new Error(`Cannot bundle runner: ${runner.logs.join("\n")}`);
  }
  await Bun.write(join(staging, "runner.js"), runner.outputs[0]);
  const assets = await buildBrowserAssets(repository);
  for (const [name, source] of [
    ["container.js", assets.container],
    ["client.mjs", assets.client],
    ["bootstrap.js", assets.bootstrap],
  ]) {
    await Bun.write(join(staging, "sandbox-assets", name), source);
  }
  for (const [name, directory] of packages) {
    await cp(directory, join(staging, "node_modules", name), {
      recursive: true,
      dereference: true,
    });
  }
  for (const name of ["runner.js", "sandbox-assets", "node_modules"]) {
    await rm(join(destination, name), { recursive: true, force: true });
    await rename(join(staging, name), join(destination, name));
  }
} finally {
  await rm(staging, { recursive: true, force: true });
}
