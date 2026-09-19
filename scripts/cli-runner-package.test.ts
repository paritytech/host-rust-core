import { afterAll, beforeAll, expect, it } from "bun:test";
import { mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import {
  decodeWireMessage,
  encodeWireMessage,
  MESSAGE_TYPE_RESPONSE,
  scale,
  VersionedRemotePermissionRequest,
  VersionedRemotePermissionResponse,
  VersionedRemotePermissionError,
} from "@parity/truapi";
import { buildBrowserAssets } from "../rust/crates/truapi-host-cli/js/browser-assets.ts";

const repository = resolve(import.meta.dir, "..");
const dependencies = (await Bun.file(join(repository, "package.json")).json())
  .devDependencies;
let directory: string;

beforeAll(async () => {
  directory = await mkdtemp(join(tmpdir(), "truapi-cli-package-"));
  const result = Bun.spawnSync(
    ["make", "cli-runner", `CLI_DIST_DIR=${directory}`],
    { cwd: repository },
  );
  if (result.exitCode !== 0) throw new Error(result.stderr.toString());
});

afterAll(async () => {
  if (directory) await rm(directory, { recursive: true, force: true });
});

it("ships each browser asset and the matching browser driver", async () => {
  const files = [
    "runner.js",
    "sandbox-assets/container.js",
    "sandbox-assets/client.mjs",
    "sandbox-assets/bootstrap.js",
    "node_modules/playwright-core/cli.js",
    "node_modules/playwright-core/browsers.json",
    "node_modules/esbuild-wasm/esbuild.wasm",
  ];
  const sizes = await Promise.all(
    files.map(async (file) => (await readFile(join(directory, file))).length),
  );
  expect(sizes.every((size) => size > 0)).toBe(true);
  const manifest = await Bun.file(
    join(directory, "node_modules/playwright-core/package.json"),
  ).json();
  expect(manifest.version).toBe(dependencies["playwright-core"]);
  const builder = await Bun.file(
    join(directory, "node_modules/esbuild-wasm/package.json"),
  ).json();
  expect(builder.version).toBe(dependencies["esbuild-wasm"]);
});

it("packages the same browser assets used by source mode", async () => {
  const expected = await buildBrowserAssets(repository);
  const [container, client, bootstrap] = await Promise.all(
    ["container.js", "client.mjs", "bootstrap.js"].map((name) =>
      readFile(join(directory, "sandbox-assets", name), "utf8"),
    ),
  );
  expect({ container, client, bootstrap }).toEqual(expected);
});

it("resolves the packaged runner without a source checkout", async () => {
  const preload = join(directory, "stack-format.js");
  await writeFile(
    preload,
    'Error.prepareStackTrace = () => "Error\\n    at package-test";',
  );
  for (const args of [[], ["--preload", preload]]) {
    const result = Bun.spawnSync(
      ["bun", ...args, join(directory, "runner.js")],
      {
        cwd: tmpdir(),
        env: { PATH: process.env.PATH },
      },
    );
    expect({
      status: result.exitCode,
      output: result.stdout.toString() + result.stderr.toString(),
    }).toEqual({
      status: 1,
      output: expect.stringContaining("TRUAPI_FRAME_URL must be set"),
    });
  }
});

it("authorizes a WebSocket round trip through the packaged browser runner", async () => {
  const authorizations: unknown[] = [];
  const server = Bun.serve<{ frames: boolean }>({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request, server) {
      if (
        server.upgrade(request, {
          data: { frames: new URL(request.url).pathname === "/frames" },
        })
      )
        return;
      return new Response(null, { status: 400 });
    },
    websocket: {
      message(socket, message) {
        if (!socket.data.frames) {
          socket.send(message);
          return;
        }
        const request = decodeWireMessage(
          new Uint8Array(message as Buffer),
        )._unsafeUnwrap();
        authorizations.push(
          VersionedRemotePermissionRequest.dec(request.payload.value),
        );
        socket.send(
          encodeWireMessage({
            ...request,
            payload: {
              ...request.payload,
              messageType: MESSAGE_TYPE_RESPONSE,
              value: scale
                .Result(
                  VersionedRemotePermissionResponse,
                  scale.CallError(VersionedRemotePermissionError),
                )
                .enc({
                  success: true,
                  value: { tag: "V1", value: { granted: true } },
                }),
            },
          })._unsafeUnwrap(),
        );
      },
    },
  });
  const script = join(directory, "websocket-product.ts");
  await writeFile(
    script,
    `
    assert(typeof process === 'undefined' && typeof Bun === 'undefined');
    await new Promise((resolve, reject) => {
      const socket = new WebSocket('ws://127.0.0.1:${server.port}/echo');
      socket.onopen = () => socket.send('packaged-websocket-ok');
      socket.onmessage = ({ data }) => {
        if (data !== 'packaged-websocket-ok') return reject(new Error('Unexpected reply'));
        socket.close();
        console.log(data);
        resolve();
      };
      socket.onerror = () => reject(new Error('WebSocket failed'));
    });
  `,
  );
  const child = Bun.spawn(["bun", join(directory, "runner.js")], {
    cwd: tmpdir(),
    env: {
      PATH: process.env.PATH,
      HOME: process.env.HOME,
      LD_LIBRARY_PATH: process.env.LD_LIBRARY_PATH,
      PLAYWRIGHT_BROWSERS_PATH: process.env.PLAYWRIGHT_BROWSERS_PATH,
      TRUAPI_FRAME_URL: `ws://127.0.0.1:${server.port}/frames`,
      TRUAPI_PRODUCT_ID: "package-test.dot",
      TRUAPI_SCRIPT: script,
      TRUAPI_SCRIPT_MODE: "trusted",
    },
    stdout: "pipe",
    stderr: "pipe",
  });
  const timeout = setTimeout(() => child.kill(), 15_000);
  try {
    const [status, output, error] = await Promise.all([
      child.exited,
      new Response(child.stdout).text(),
      new Response(child.stderr).text(),
    ]);
    expect({ status, output, authorizations }, error).toEqual({
      status: 0,
      output: "packaged-websocket-ok\n",
      authorizations: [
        {
          tag: "V1",
          value: {
            permission: { tag: "Remote", value: { domains: ["127.0.0.1"] } },
          },
        },
      ],
    });
  } finally {
    clearTimeout(timeout);
    child.kill();
    server.stop(true);
  }
}, 20_000);

it("ships a runnable browser installer with its dynamic dependencies", () => {
  const result = Bun.spawnSync(
    [
      "bun",
      join(directory, "node_modules/playwright-core/cli.js"),
      "--version",
    ],
    { cwd: tmpdir() },
  );
  expect({
    status: result.exitCode,
    output: result.stdout.toString().trim(),
  }).toEqual({
    status: 0,
    output: `Version ${dependencies["playwright-core"]}`,
  });
});

it("produces a valid browser client module with complete exports", () => {
  const result = Bun.spawnSync([
    "node",
    "--check",
    join(directory, "sandbox-assets/client.mjs"),
  ]);
  expect({ status: result.exitCode, error: result.stderr.toString() }).toEqual({
    status: 0,
    error: "",
  });
});

it("ships a portable product builder that works without a checkout", () => {
  const entrypoint = join(directory, "node_modules/esbuild-wasm/lib/main.js");
  const source = `const { transform, stop } = require(${JSON.stringify(entrypoint)});
    const result = await transform('const value: string = "browser";', { loader: 'ts' });
    console.log(result.code.trim());
    stop();`;
  const result = Bun.spawnSync(["bun", "--eval", source], { cwd: tmpdir() });
  expect({
    status: result.exitCode,
    output: result.stdout.toString().trim(),
  }).toEqual({ status: 0, output: 'const value = "browser";' });
});

it("fails closed when an installed sandbox asset is missing", async () => {
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request, server) {
      if (server.upgrade(request)) return;
      return new Response(null, { status: 400 });
    },
    websocket: { message() {} },
  });
  const asset = join(directory, "sandbox-assets/container.js");
  const backup = `${asset}.backup`;
  const script = join(directory, "product.ts");
  await writeFile(script, 'console.log("product must not run");');
  await rename(asset, backup);
  try {
    const child = Bun.spawn(["bun", join(directory, "runner.js")], {
      cwd: tmpdir(),
      env: {
        PATH: process.env.PATH,
        TRUAPI_FRAME_URL: `ws://127.0.0.1:${server.port}`,
        TRUAPI_PRODUCT_ID: "package-test.dot",
        TRUAPI_SCRIPT: script,
      },
      stdout: "pipe",
      stderr: "pipe",
    });
    const [status, output, error] = await Promise.all([
      child.exited,
      new Response(child.stdout).text(),
      new Response(child.stderr).text(),
    ]);
    expect({ status, output, error }).toEqual({
      status: 1,
      output: "",
      error: expect.stringContaining(
        "Sandbox assets are missing beside runner.js; reinstall truapi-host",
      ),
    });
  } finally {
    await rename(backup, asset);
    server.stop(true);
  }
});
