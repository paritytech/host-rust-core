// Node half of the test host: serves the page the Playwright fixture drives.
//
// The browser entry is bundled with esbuild at startup rather than served as
// loose ESM. Two of the modules it reaches import bare specifiers
// (`@parity/truapi`, `neverthrow`), and resolving those in the browser would
// mean an import map pointing into `node_modules` -- which breaks under
// pnpm's symlinked layout, the layout the consuming suites actually use.
// Bundling resolves them the same way the rest of the toolchain does.

import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { dirname, extname, join, normalize, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
/**
 * Built artefacts always live in `dist`, whether this module is running from
 * `dist/testing` or straight from `src/testing` under a TS runner. Both sit two
 * levels below the package root, so resolve that and go down into `dist`.
 */
const distRoot = resolve(__dirname, "../..", "dist");

/** Options for {@link createTestHostServer}. */
export interface TestHostServerOptions {
  /** Port to listen on. `0` (the default) picks a free one. */
  port?: number;
}

/** A running test host server. */
export interface TestHostServer {
  /** Base URL; the fixture appends `?product=` and `?mock=`. */
  url: string;
  /** Stop listening. */
  close(): Promise<void>;
}

const PAGE = `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>TrUAPI test host</title>
    <style>
      html, body, #product-container { margin: 0; height: 100%; }
      #product-container > iframe { width: 100%; height: 100%; border: 0; }
    </style>
  </head>
  <body>
    <div id="product-container"></div>
    <script type="module" src="/test-host.js"></script>
  </body>
</html>
`;

const CONTENT_TYPES: Record<string, string> = {
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".json": "application/json; charset=utf-8",
  ".ts": "text/plain; charset=utf-8",
};

/** Bundle the browser entry, resolving its bare imports. */
async function bundleEntry(): Promise<string> {
  const { build } = await import("esbuild");
  const result = await build({
    entryPoints: [join(distRoot, "testing/browser-entry.js")],
    bundle: true,
    format: "esm",
    platform: "browser",
    write: false,
    // The WASM glue is fetched at runtime from `/wasm/testing/`, not bundled:
    // it loads a sibling `.wasm` by relative URL and esbuild would break that.
    external: ["./wasm/*", "*.wasm"],
  });
  const [output] = result.outputFiles;
  if (!output) throw new Error("esbuild produced no output for the test host");
  return output.text;
}

/**
 * Start the test host server.
 *
 * ```ts
 * const server = await createTestHostServer();
 * const test = base.extend(createTestHostFixture({
 *   productUrl: "http://127.0.0.1:5173",
 *   hostUrl: server.url,
 * }));
 * ```
 */
export async function createTestHostServer(
  options: TestHostServerOptions = {},
): Promise<TestHostServer> {
  const bundle = await bundleEntry();

  const server = createServer((req, res) => {
    const path = new URL(req.url ?? "/", "http://127.0.0.1").pathname;

    if (path === "/test-host.js") {
      res.writeHead(200, { "Content-Type": CONTENT_TYPES[".js"] });
      res.end(bundle);
      return;
    }

    // The WASM bundle and its glue are served from disk so the browser fetches
    // the same artifact the build produced.
    if (path.startsWith("/wasm/")) {
      void serveFromDist(path.slice(1), res);
      return;
    }

    res.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      // The product runs cross-origin in an iframe; without this the browser
      // refuses to delegate clipboard access however the iframe is marked.
      "Permissions-Policy": "clipboard-read=*, clipboard-write=*",
    });
    res.end(PAGE);
  });

  const url = await new Promise<string>((resolveUrl, reject) => {
    server.once("error", reject);
    server.listen(options.port ?? 0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        reject(new Error("test host server reported no address"));
        return;
      }
      resolveUrl(`http://127.0.0.1:${address.port}`);
    });
  });

  return {
    url,
    close: () =>
      new Promise<void>((done, reject) => {
        server.close((err) => (err ? reject(err) : done()));
      }),
  };
}

/** Serve one file from `dist`, refusing anything that escapes it. */
async function serveFromDist(
  relativePath: string,
  res: import("node:http").ServerResponse,
): Promise<void> {
  const target = resolve(distRoot, normalize(relativePath));
  if (target !== distRoot && !target.startsWith(distRoot + sep)) {
    res.writeHead(403).end("forbidden");
    return;
  }
  try {
    const body = await readFile(target);
    res.writeHead(200, {
      "Content-Type":
        CONTENT_TYPES[extname(target)] ?? "application/octet-stream",
    });
    res.end(body);
  } catch {
    res.writeHead(404).end("not found");
  }
}
