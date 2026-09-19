import { join } from "node:path";

export interface BrowserAssets {
  container: string;
  client: string;
  bootstrap: string;
}

export async function buildBrowserAssets(
  repository: string,
): Promise<BrowserAssets> {
  const { build } = await import("esbuild-wasm");

  async function bundle(
    entrypoint: string,
    format: "iife" | "esm",
    external: string[] = [],
  ): Promise<string> {
    const result = await build({
      entryPoints: [join(repository, entrypoint)],
      absWorkingDir: repository,
      bundle: true,
      platform: "browser",
      target: format === "iife" ? "es2020" : "es2022",
      format,
      external,
      define: { "process.env.NODE_ENV": '"production"' },
      write: false,
    });
    return result.outputFiles[0].text;
  }

  const [container, client, bootstrap] = await Promise.all([
    bundle("js/container/src/index.ts", "iife"),
    bundle("js/packages/truapi/src/index.ts", "esm"),
    bundle("rust/crates/truapi-host-cli/js/browser-bootstrap.ts", "esm", [
      "@parity/truapi",
    ]),
  ]);
  return { container, client, bootstrap };
}
