#!/usr/bin/env node
// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { spawnSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  statSync,
  unlinkSync,
} from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, resolve, sep } from "node:path";

const repoRoot = resolve(import.meta.dirname, "..");
const bundle =
  process.env.TRUAPI_IOS_E2E_BUNDLE ?? "io.pcf.polkadotapp.develop";
const app =
  process.env.TRUAPI_IOS_E2E_APP ??
  resolve(
    repoRoot,
    "hosts/ios/build/DerivedData/Build/Products/Debug-iphonesimulator/polkadot-app.app",
  );
const productRoot = resolve(
  repoRoot,
  process.env.TRUAPI_IOS_E2E_CHAT_PRODUCT_DIR ?? "playground",
);
const productHost =
  process.env.TRUAPI_IOS_E2E_CHAT_PRODUCT_HOST ?? "truapi-playground.dot";
const productName =
  process.env.TRUAPI_IOS_E2E_CHAT_PRODUCT_NAME ?? "TrUAPI Playground";
const roomId = process.env.TRUAPI_IOS_E2E_CHAT_ROOM_ID ?? "truapi-playground";
const message = process.env.TRUAPI_IOS_E2E_CHAT_MESSAGE ?? "!echo hello";
const expectedReply =
  process.env.TRUAPI_IOS_E2E_CHAT_EXPECTED_REPLY ?? "Echo: hello";
const expectedStartupMessage =
  process.env.TRUAPI_IOS_E2E_CHAT_EXPECTED_STARTUP_MESSAGE ??
  'Chat API checks passed. Send "!echo <message>" to test actions.';
const expectCustomRenderer =
  process.env.TRUAPI_IOS_E2E_CHAT_EXPECT_CUSTOM_RENDERER !== "0";
const worker = resolve(productRoot, "out/worker/index.js");
const productUrl =
  process.env.TRUAPI_IOS_E2E_CHAT_PRODUCT_URL ?? "http://127.0.0.1:3100";
const screenshot = resolve(
  repoRoot,
  process.env.TRUAPI_IOS_E2E_CHAT_SCREENSHOT ??
    "artifacts/truapi-playground-chat.png",
);

if (!existsSync(app)) {
  throw new Error(`iOS app bundle not found: ${app}`);
}
if (!existsSync(resolve(productRoot, "package.json"))) {
  throw new Error(`Chat product source not found: ${productRoot}`);
}

const linkedTruapiRoot = process.env.TRUAPI_IOS_E2E_CHAT_TRUAPI_DIR;
if (linkedTruapiRoot) {
  const truapiRoot = resolve(repoRoot, linkedTruapiRoot);
  run("yarn", ["build"], { cwd: truapiRoot });
  run("yarn", ["link"], { cwd: truapiRoot });
  run("yarn", ["link", "@parity/truapi"], { cwd: productRoot });
}

if (process.env.TRUAPI_IOS_E2E_SKIP_PRODUCT_BUILD !== "1") {
  run("yarn", ["build"], { cwd: productRoot });
}
if (!existsSync(worker)) {
  throw new Error(`Chat product worker not found after build: ${worker}`);
}

const device = selectSimulator();
run("open", ["-a", "Simulator", "--args", "-CurrentDeviceUDID", device.udid], {
  stdio: "ignore",
});
if (device.state !== "Booted") {
  run("xcrun", ["simctl", "boot", device.udid]);
}
run("xcrun", ["simctl", "bootstatus", device.udid, "-b"]);
run("xcrun", ["simctl", "install", device.udid, app]);

const appData = capture("xcrun", [
  "simctl",
  "get_app_container",
  device.udid,
  bundle,
  "data",
]).trim();
const connectionMarkers = [
  resolve(appData, "tmp/truapi-e2e", `connected-app-${productHost}`),
  resolve(appData, "tmp/truapi-e2e", `connected-chat-${productHost}`),
];
const customRendererMarker = resolve(
  appData,
  "tmp/truapi-e2e/custom-renderer-update",
);
for (const marker of [...connectionMarkers, customRendererMarker]) {
  if (existsSync(marker)) {
    unlinkSync(marker);
  }
}
const workerDestination = resolve(
  appData,
  "Library/Application Support/Products",
  productHost,
  "ChatExtension/index.js",
);
mkdirSync(resolve(workerDestination, ".."), { recursive: true });
cpSync(worker, workerDestination);

const userDataDatabase = resolve(
  appData,
  "Library/Application Support/group.pcf.polkadotapp/CoreData/UserDataModel.sqlite",
);
const chatIdentifier = `1:${productHost}:${roomId}`;
const messageWatermark = existsSync(userDataDatabase)
  ? latestMessageId(userDataDatabase, chatIdentifier)
  : 0;

const productServer = await startProductServer(
  productUrl,
  resolve(productRoot, "out"),
);
try {
  run(
    "xcrun",
    ["simctl", "launch", "--terminate-running-process", device.udid, bundle],
    {
      env: {
        ...process.env,
        SIMCTL_CHILD_RUST_BACKTRACE: "1",
        SIMCTL_CHILD_TRUAPI_IOS_E2E_BROWSE: "1",
        SIMCTL_CHILD_TRUAPI_IOS_E2E_PRODUCT_HOST: productHost,
        SIMCTL_CHILD_TRUAPI_IOS_E2E_PRODUCT_URL: productUrl,
        SIMCTL_CHILD_TRUAPI_IOS_E2E_CHAT_PRODUCT_HOST: productHost,
        SIMCTL_CHILD_TRUAPI_IOS_E2E_CHAT_PRODUCT_NAME: productName,
        SIMCTL_CHILD_TRUAPI_IOS_E2E_CHAT_ROOM_ID: roomId,
        SIMCTL_CHILD_TRUAPI_IOS_E2E_CHAT_MESSAGE: message,
        SIMCTL_CHILD_TRUAPI_IOS_E2E_OPEN_CHAT: "1",
        SIMCTL_CHILD_TRUAPI_IOS_E2E_RUNTIME_MARKERS: "1",
      },
    },
  );

  await waitForFiles(connectionMarkers, 30_000);
  if (expectedStartupMessage) {
    await waitForReply(
      userDataDatabase,
      chatIdentifier,
      messageWatermark,
      expectedStartupMessage,
    );
  }
  await waitForReply(
    userDataDatabase,
    chatIdentifier,
    messageWatermark,
    expectedReply,
  );
  if (expectCustomRenderer) {
    await waitForFiles([customRendererMarker], 30_000);
  }
  await delay(2_000);
  mkdirSync(dirname(screenshot), { recursive: true });
  run("xcrun", ["simctl", "io", device.udid, "screenshot", screenshot]);
} finally {
  productServer?.close();
}

console.log(
  JSON.stringify({
    device: device.name,
    deviceId: device.udid,
    app,
    bundle,
    productHost,
    productName,
    roomId,
    message,
    expectedReply,
    expectedStartupMessage,
    customRendererVerified: expectCustomRenderer,
    productUrl,
    connectedExecutions: ["App", "Chat"],
    worker,
    workerDestination,
    screenshot,
    verified: true,
  }),
);

async function startProductServer(urlString, root) {
  const url = new URL(urlString);
  if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(url.hostname)) {
    throw new Error(
      `Product URL must be loopback for this E2E test: ${urlString}`,
    );
  }

  try {
    const response = await fetch(urlString);
    if (response.ok && (await response.text()).includes(productName)) {
      return null;
    }
    throw new Error(`${urlString} is serving a different application`);
  } catch (error) {
    if (
      error instanceof Error &&
      error.message.includes("different application")
    ) {
      throw error;
    }
  }

  const server = createServer((request, response) => {
    try {
      const pathname = decodeURIComponent(
        new URL(request.url ?? "/", urlString).pathname,
      );
      let file = resolve(root, `.${pathname}`);
      if (file !== root && !file.startsWith(`${root}${sep}`)) {
        response.writeHead(403).end();
        return;
      }
      if (statSync(file).isDirectory()) {
        file = resolve(file, "index.html");
      }
      response.setHeader("Content-Type", contentType(file));
      const content = readFileSync(file);
      response.end(
        extname(file) === ".html"
          ? injectAppConnectionProbe(content.toString("utf8"))
          : content,
      );
    } catch {
      response.writeHead(404).end();
    }
  });
  await new Promise((resolveListen, reject) => {
    server.once("error", reject);
    server.listen(Number(url.port || 80), url.hostname, resolveListen);
  });
  return server;
}

function injectAppConnectionProbe(html) {
  const probe = `<script>
    (() => {
      let attempts = 0;
      const timer = setInterval(() => {
        const button = document.querySelector(
          '[data-testid="run-storage-string-write-read"]',
        );
        if (button) {
          clearInterval(timer);
          button.click();
        } else if (++attempts >= 100) {
          clearInterval(timer);
        }
      }, 100);
    })();
  </script>`;
  return html.replace("</body>", `${probe}</body>`);
}

function contentType(file) {
  switch (extname(file)) {
    case ".html":
      return "text/html; charset=utf-8";
    case ".js":
      return "text/javascript; charset=utf-8";
    case ".css":
      return "text/css; charset=utf-8";
    case ".json":
      return "application/json";
    case ".png":
      return "image/png";
    case ".svg":
      return "image/svg+xml";
    default:
      return "application/octet-stream";
  }
}

async function waitForFiles(files, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (files.every(existsSync)) {
      return;
    }
    await delay(250);
  }
  throw new Error(
    `Timed out waiting for execution connections: ${files.join(", ")}`,
  );
}

function latestMessageId(database, identifier) {
  const query = `
    SELECT COALESCE(MAX(message.Z_PK), 0)
    FROM ZCDCHATMESSAGE AS message
    JOIN ZCDCHAT AS chat ON chat.Z_PK = message.ZCHAT
    WHERE chat.ZIDENTIFIER = ${sqlString(identifier)};
  `;
  const value = capture("sqlite3", [database, query]).trim();
  return Number.parseInt(value, 10) || 0;
}

async function waitForReply(database, identifier, afterMessageId, reply) {
  const expectedPayload = Buffer.concat([
    Buffer.of(0),
    encodeScaleCompact(Buffer.byteLength(reply, "utf8")),
    Buffer.from(reply, "utf8"),
  ])
    .toString("hex")
    .toUpperCase();
  const deadline = Date.now() + 30_000;

  while (Date.now() < deadline) {
    if (existsSync(database)) {
      const query = `
        SELECT COUNT(*)
        FROM ZCDCHATMESSAGE AS message
        JOIN ZCDCHAT AS chat ON chat.Z_PK = message.ZCHAT
        JOIN ZCDMESSAGECONTENT AS content ON content.Z_PK = message.ZCONTENT
        WHERE chat.ZIDENTIFIER = ${sqlString(identifier)}
          AND message.Z_PK > ${afterMessageId}
          AND hex(content.ZDATA) = ${sqlString(expectedPayload)};
      `;
      if (capture("sqlite3", [database, query]).trim() !== "0") {
        return;
      }
    }
    await delay(250);
  }

  throw new Error(
    `Timed out waiting for ${JSON.stringify(reply)} in ${identifier}`,
  );
}

function delay(milliseconds) {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, milliseconds));
}

function encodeScaleCompact(value) {
  if (value < 1 << 6) {
    return Buffer.of(value << 2);
  }
  if (value < 1 << 14) {
    const encoded = (value << 2) | 1;
    const result = Buffer.allocUnsafe(2);
    result.writeUInt16LE(encoded);
    return result;
  }
  if (value < 1 << 30) {
    const encoded = value * 4 + 2;
    const result = Buffer.allocUnsafe(4);
    result.writeUInt32LE(encoded);
    return result;
  }
  throw new Error("Expected reply is too large for this E2E assertion");
}

function sqlString(value) {
  return `'${value.replaceAll("'", "''")}'`;
}

function selectSimulator() {
  const requested =
    process.env.TRUAPI_IOS_E2E_DEVICE ?? process.env.IOS_SIMULATOR_DEVICE;
  const simulatorList = JSON.parse(
    capture("xcrun", ["simctl", "list", "devices", "available", "-j"]),
  );
  const devices = Object.values(simulatorList.devices)
    .flat()
    .filter(
      (candidate) =>
        candidate.isAvailable && candidate.name.startsWith("iPhone"),
    );
  const selected = requested
    ? devices.find(
        (candidate) =>
          candidate.udid === requested || candidate.name === requested,
      )
    : (devices.find((candidate) => candidate.state === "Booted") ?? devices[0]);

  if (!selected) {
    throw new Error(
      requested
        ? `Requested iPhone simulator is unavailable: ${requested}`
        : "No available iPhone simulator found",
    );
  }
  return selected;
}

function capture(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with ${result.status}`,
    );
  }
  return result.stdout;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: "inherit", ...options });
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with ${result.status}`,
    );
  }
}
