import { lstat, readFile, realpath } from "node:fs/promises";
import { builtinModules } from "node:module";
import {
  dirname,
  extname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from "node:path";
import { build } from "esbuild-wasm";

const hostModules = new Set(
  builtinModules.flatMap((name) => [name, `node:${name}`]),
);
const loaders: Record<string, "js" | "jsx" | "ts" | "tsx" | "json"> = {
  ".js": "js",
  ".mjs": "js",
  ".cjs": "js",
  ".jsx": "jsx",
  ".ts": "ts",
  ".mts": "ts",
  ".cts": "ts",
  ".tsx": "tsx",
  ".json": "json",
};

function within(path: string, root: string): boolean {
  const fromRoot = relative(root, path);
  return (
    fromRoot === "" ||
    (fromRoot !== ".." &&
      !fromRoot.startsWith(`..${sep}`) &&
      !isAbsolute(fromRoot))
  );
}

async function dependencyRoots(directory: string): Promise<string[]> {
  const roots: string[] = [];
  for (;;) {
    const modules = join(directory, "node_modules");
    if (
      await lstat(modules).then(
        (entry) => entry.isDirectory(),
        () => false,
      )
    ) {
      roots.push(modules);
    }
    const parent = dirname(directory);
    if (parent === directory) return roots;
    directory = parent;
  }
}

export async function buildProductScript(script: string): Promise<string> {
  const entrypoint = await realpath(resolve(script));
  const root = dirname(entrypoint);
  const roots = [root, ...(await dependencyRoots(root))];
  const result = await build({
    entryPoints: [entrypoint],
    absWorkingDir: root,
    bundle: true,
    platform: "browser",
    target: "es2022",
    tsconfigRaw: {},
    format: "esm",
    write: false,
    logLevel: "silent",
    external: ["@parity/truapi"],
    plugins: [
      {
        name: "product-inputs",
        setup(build) {
          build.onResolve({ filter: /./ }, ({ path, with: attributes }) => {
            if (
              hostModules.has(path) ||
              path.startsWith("node:") ||
              path.startsWith("bun:")
            ) {
              throw new Error(
                `Host module ${path} is unavailable in sandboxed product scripts`,
              );
            }
            if (attributes.type === "macro")
              throw new Error(
                "Product macros are unavailable in sandboxed scripts",
              );
            if (path === "@parity/truapi") return { path, external: true };
          });
          build.onLoad({ filter: /./ }, async ({ path }) => {
            const canonical = await realpath(path);
            if (!roots.some((allowed) => within(canonical, allowed))) {
              throw new Error(`Import outside the product directory: ${path}`);
            }
            const loader = loaders[extname(canonical)];
            if (!loader) throw new Error(`Unsupported product module: ${path}`);
            return {
              contents: await readFile(canonical, "utf8"),
              loader,
              resolveDir: dirname(canonical),
            };
          });
        },
      },
    ],
  });
  if (result.outputFiles.length !== 1) {
    throw new Error("Product scripts must build to a single JavaScript module");
  }
  return result.outputFiles[0].text;
}
