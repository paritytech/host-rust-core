import { expect, test } from "bun:test";
import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ServerWebSocket } from "bun";
import {
  decodeWireMessage,
  encodeWireMessage,
} from "../../../../js/packages/truapi/src/transport.ts";

const runner = fileURLToPath(new URL("./runner.ts", import.meta.url));

test("standard host discovery is ready before importing a script", async () => {
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
      message(connection, frame) {
        const message = decodeWireMessage(
          new Uint8Array(frame as Uint8Array),
        )._unsafeUnwrap();
        if (message.payload.messageType !== 0) return;
        connection.send(
          encodeWireMessage({
            ...message,
            payload: {
              ...message.payload,
              messageType: 1,
              value: Uint8Array.of(0, 0),
            },
          })._unsafeUnwrap(),
        );
      },
    },
  });
  const script = join(directory, "script.ts");
  await writeFile(
    script,
    `assert(window === window.top);
assert(window.__HOST_WEBVIEW_MARK__);
assert(window.__HOST_API_CLIENT__.client === truapi);
assert(window.__HOST_API_PORT__ instanceof MessagePort);
let unsubscribe;
const closed = new Promise(resolve => {
  unsubscribe = window.__HOST_API_CLIENT__.subscribeConnectionStatus(status => {
    if (status === "disconnected") resolve();
  });
});
console.log("ready");
await closed;
unsubscribe();
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
