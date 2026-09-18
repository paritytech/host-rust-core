import { expect, test } from "bun:test";
import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ServerWebSocket } from "bun";
import { version } from "../../../../js/packages/truapi/package.json";

const runner = fileURLToPath(new URL("./runner.ts", import.meta.url));

test("a script observes its client version and a real connection closing", async () => {
  const directory = await mkdtemp(join(tmpdir(), "host-script-lifecycle-"));
  let socket: ServerWebSocket<undefined> | undefined;
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request, server) {
      if (server.upgrade(request)) return;
      return new Response("WebSocket required", { status: 400 });
    },
    websocket: {
      open(connection) {
        socket = connection;
      },
      message() {},
    },
  });
  const script = join(directory, "script.ts");
  await writeFile(
    script,
    `assert(host.apiVersion === ${JSON.stringify(version)});
assert(!host.signal.aborted);
const closed = new Promise(resolve => host.signal.addEventListener("abort", resolve, { once: true }));
console.log("ready");
await closed;
assert(host.signal.reason instanceof Error);
console.log("disconnected");
`,
  );
  const child = spawn(process.execPath, [runner], {
    env: {
      ...process.env,
      TRUAPI_FRAME_URL: `ws://127.0.0.1:${server.port}`,
      TRUAPI_PRODUCT_ID: "script-lifecycle",
      TRUAPI_SCRIPT: script,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk: Buffer) => {
    stdout += chunk.toString();
    if (stdout.includes("ready\n")) socket?.close();
  });
  child.stderr.on("data", (chunk: Buffer) => {
    stderr += chunk.toString();
  });
  try {
    const exitCode = await new Promise<number | null>((resolve, reject) => {
      child.once("error", reject);
      child.once("close", resolve);
    });
    expect({ exitCode, stdout, stderr }).toEqual({
      exitCode: 0,
      stdout: "ready\ndisconnected\n",
      stderr: "",
    });
  } finally {
    child.kill();
    server.stop(true);
    await rm(directory, { recursive: true, force: true });
  }
});
