#!/usr/bin/env node
// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import {
  DEFAULT_AVD,
  DEFAULT_PACKAGE,
  chatIdHex,
  clearAppData,
  clearLogcat,
  decodeSqliteHexRows,
  ensureEmulator,
  forceStop,
  grantPermission,
  installApk,
  removeReversePort,
  reversePort,
  runAsSqlite,
  screencap,
  sendBroadcast,
  startActivity,
  startDeepLink,
  waitForLogcatMessage,
  waitForProcess,
} from "./lib/android-emulator.mjs";
import {
  CHAT_DIAGNOSIS_HEADING,
  REGISTER_BOT_GAP,
  labelChatDiagnosisReport,
} from "./lib/chat-diagnosis-report.mjs";
import { delay, runAsync, waitFor } from "./lib/process.mjs";
import { startProductServer } from "./lib/product-server.mjs";

const repoRoot = resolve(import.meta.dirname, "..");

const DEBUG_ACTION = "io.paritytech.polkadotapp.debug.E2E";
const E2E_TAG = "truapi.e2e";
const CORE_TAG = "truapi.core";
const DEFAULT_RECEIVER =
  "io.paritytech.polkadotapp.app.debug.e2e.E2EHookReceiver";
const DEFAULT_ACTIVITY =
  "io.paritytech.polkadotapp.app.root.presentation.root.RootActivity";
const DEFAULT_USERNAME = "truapi-e2e";
const CORE_MARKER = "truapi.ws_bridge.connection_open";
const DATABASE = "databases/app_v2.db";

/** Acks the debug hooks log under `E2E_TAG`; the formats live in `E2EAcks`. */
const ACKS = {
  seedIdentityDone: "seed_identity done",
  productRegistered: (id) => `product registered id=${id}`,
  messageQueued: (id, room) => `message queued product=${id} room=${room}`,
  messageDelivered: (id, room) =>
    `message delivered product=${id} room=${room}`,
  customRendererUpdate: (id) => `custom_renderer_update product=${id}`,
};

const TIMEOUTS = {
  ack: 60_000,
  core: 60_000,
  render: 30_000,
  chatMessage: 60_000,
  foregroundSettle: 3_000,
  relaunchSettle: 1_000,
  screenshotSettle: 2_000,
};

const packageName = process.env.TRUAPI_ANDROID_E2E_PACKAGE ?? DEFAULT_PACKAGE;
const receiver = process.env.TRUAPI_ANDROID_E2E_RECEIVER ?? DEFAULT_RECEIVER;
const avd = process.env.TRUAPI_ANDROID_E2E_AVD ?? DEFAULT_AVD;
const requestedSerial = process.env.TRUAPI_ANDROID_E2E_DEVICE;
const username = process.env.TRUAPI_ANDROID_E2E_USERNAME ?? DEFAULT_USERNAME;
const apk = resolve(
  repoRoot,
  process.env.TRUAPI_ANDROID_E2E_APK ??
    "hosts/android/app/build/outputs/apk/vanilla/debug/app-vanilla-debug.apk",
);
const productRoot = resolve(
  repoRoot,
  process.env.TRUAPI_ANDROID_E2E_CHAT_PRODUCT_DIR ?? "playground",
);
const productHost =
  process.env.TRUAPI_ANDROID_E2E_CHAT_PRODUCT_HOST ?? "truapi-playground.dot";
const productName =
  process.env.TRUAPI_ANDROID_E2E_CHAT_PRODUCT_NAME ?? "TrUAPI Playground";
const roomId =
  process.env.TRUAPI_ANDROID_E2E_CHAT_ROOM_ID ?? "truapi-playground";
const expectDiagnosis = process.env.TRUAPI_ANDROID_E2E_CHAT_DIAGNOSIS !== "0";
const message =
  process.env.TRUAPI_ANDROID_E2E_CHAT_MESSAGE ??
  (expectDiagnosis ? "!diagnose" : "!echo hello");
const expectedReply =
  process.env.TRUAPI_ANDROID_E2E_CHAT_EXPECTED_REPLY ?? "Echo: hello";
const expectedStartupMessage =
  process.env.TRUAPI_ANDROID_E2E_CHAT_EXPECTED_STARTUP_MESSAGE ?? "";
const expectCustomRenderer =
  process.env.TRUAPI_ANDROID_E2E_CHAT_EXPECT_CUSTOM_RENDERER !== "0";
const worker = resolve(productRoot, "out/worker/index.js");
const productUrl =
  process.env.TRUAPI_ANDROID_E2E_CHAT_PRODUCT_URL ?? "http://127.0.0.1:3100";
const screenshot = resolve(
  repoRoot,
  process.env.TRUAPI_ANDROID_E2E_CHAT_SCREENSHOT ??
    "artifacts/truapi-playground-android-chat.png",
);
const reportPath = resolve(
  repoRoot,
  process.env.TRUAPI_ANDROID_E2E_CHAT_REPORT ??
    "playground/test-results/android-chat/diagnosis-report.md",
);

const url = new URL(productUrl);
if (url.hostname !== "127.0.0.1") {
  throw new Error(
    `The Android app only allows cleartext to 127.0.0.1; got ${url.hostname} in ${productUrl}`,
  );
}

const launcherActivity = `${packageName}/${DEFAULT_ACTIVITY}`;
const receiverComponent = `${packageName}/${receiver}`;
const workerUrl = `${productUrl.replace(/\/$/, "")}/worker/index.js`;
// ChatId bytes: `ChatExtension:<ProductId.toChatExtensionId()>:<roomId>`.
const extensionId = `ProductBot_${productHost}`;
const chatHex = chatIdHex(extensionId, roomId);
const productPort = url.port || "80";
// The hook acks spell a missing room as "-".
const roomMarker = roomId || "-";

const receiverHint =
  `Nothing in ${packageName} acknowledged ${DEBUG_ACTION} at ${receiverComponent}.\n` +
  `Check that the installed build exports that debug receiver, or point ` +
  `TRUAPI_ANDROID_E2E_RECEIVER at the right class.`;

if (!existsSync(resolve(productRoot, "package.json"))) {
  throw new Error(`Chat product source not found: ${productRoot}`);
}

let currentStep = "startup";
let productServer;
let serial;

function step(name) {
  currentStep = name;
  console.log(`==> ${name}`);
}

try {
  step("build the chat product");
  const productBuild =
    process.env.TRUAPI_ANDROID_E2E_SKIP_PRODUCT_BUILD !== "1"
      ? runAsync("yarn", ["build"], { cwd: productRoot })
      : Promise.resolve();
  productBuild.catch(() => {});

  step("boot the emulator");
  serial = await ensureEmulator({
    avd,
    serial: requestedSerial,
    log: (line) => console.log(`    ${line}`),
  });
  console.log(`    device ${serial}`);

  await productBuild;
  if (!existsSync(worker)) {
    throw new Error(`Chat product worker not found after build: ${worker}`);
  }

  step(`serve ${productRoot}/out at ${productUrl}`);
  productServer = await startProductServer(
    productUrl,
    resolve(productRoot, "out"),
    productName,
  );

  step(`adb reverse tcp:${productPort} tcp:${productPort}`);
  reversePort(serial, productPort);

  step(`install ${apk}`);
  installApk(serial, apk);

  // A warm emulator must not go green on the rows a previous run left behind.
  step(`clear ${packageName} app data`);
  clearAppData(serial, packageName);

  step("grant POST_NOTIFICATIONS");
  const grant = grantPermission(
    serial,
    packageName,
    "android.permission.POST_NOTIFICATIONS",
  );
  if (!grant.granted) {
    console.log(`    not granted (ignored): ${grant.output}`);
  }

  // Seeding reads the People chain, and chain connections need the FOREGROUND.
  step("start the app so its chain connections come up");
  startActivity(serial, launcherActivity);
  await waitForProcess(serial, packageName);
  await delay(TIMEOUTS.foregroundSettle);

  step("clear logcat");
  clearLogcat(serial);

  step(`debug hooks: seed identity, queue ${JSON.stringify(message)}, register ${productHost}`);
  sendDebugHooks([
    ["--ez", "seed_identity", "true"],
    ["--es", "username", username],
    ["--es", "product_id", productHost],
    ["--es", "product_name", productName],
    ["--es", "worker_url", workerUrl],
    ["--es", "room_id", roomId],
    ["--es", "message", message],
  ]);

  step("wait for seed_identity done");
  await awaitHookAck(ACKS.seedIdentityDone);

  step("wait for message queued");
  await awaitHookAck(ACKS.messageQueued(productHost, roomMarker));

  step("wait for product registered");
  await awaitHookAck(ACKS.productRegistered(productHost));

  // The splash routes on onboarding state once, at start.
  step("relaunch the app on the seeded identity");
  forceStop(serial, packageName);
  clearLogcat(serial);
  startActivity(serial, launcherActivity);
  await waitForProcess(serial, packageName);
  await delay(TIMEOUTS.relaunchSettle);

  const watermark = chatMessageWatermark();

  // The queue lived in the process the relaunch killed, so send it again.
  step(`queue ${JSON.stringify(message)} again in the relaunched process`);
  sendDebugHooks([
    ["--es", "product_id", productHost],
    ["--es", "room_id", roomId],
    ["--es", "message", message],
  ]);

  step(`wait for ${CORE_MARKER}`);
  await waitForLogcatMessage(serial, {
    tags: [CORE_TAG, E2E_TAG],
    marker: CORE_MARKER,
    timeoutMs: TIMEOUTS.core,
    errorTag: E2E_TAG,
    hint: "The product worker never connected to the shared core.",
  });

  step("wait for the queued message to be delivered");
  await waitForLogcatMessage(serial, {
    tags: [E2E_TAG],
    marker: ACKS.messageDelivered(productHost, roomMarker),
    timeoutMs: TIMEOUTS.ack,
    errorTag: E2E_TAG,
  });

  // The report is posted only once the custom message renders on screen.
  step("open the chat deeplink");
  startDeepLink(serial, `polkadotapp://chat?chatId=${chatHex}`);

  if (expectCustomRenderer) {
    step("wait for custom_renderer_update");
    await waitForLogcatMessage(serial, {
      tags: [E2E_TAG],
      marker: ACKS.customRendererUpdate(productHost),
      timeoutMs: TIMEOUTS.render,
      errorTag: E2E_TAG,
      hint: "The custom-rendered widget never reached the chat feed.",
    });
  }

  if (expectDiagnosis) {
    step("wait for the diagnosis report in chat_messages");
    const report = await waitForChatMessage(CHAT_DIAGNOSIS_HEADING, watermark);
    assertNotTruncated(report);
    const hostReport = labelChatDiagnosisReport(report, "Android", {
      acceptedFailures: REGISTER_BOT_GAP,
    });
    mkdirSync(dirname(reportPath), { recursive: true });
    writeFileSync(reportPath, `${hostReport}\n`);
    console.log(`    report written to ${reportPath}`);
  } else {
    if (expectedStartupMessage) {
      step("wait for the expected startup message");
      await waitForChatMessage(expectedStartupMessage, watermark);
    }
    step(`wait for ${JSON.stringify(expectedReply)} in chat_messages`);
    await waitForChatMessage(expectedReply, watermark);
  }

  step("screenshot");
  await delay(TIMEOUTS.screenshotSettle);
  mkdirSync(dirname(screenshot), { recursive: true });
  screencap(serial, screenshot);
} catch (error) {
  productServer?.close();
  if (serial) {
    removeReversePort(serial, productPort);
  }
  console.error(
    `\nAndroid chat e2e FAILED at step: ${currentStep}\n${error instanceof Error ? (error.stack ?? error.message) : error}`,
  );
  process.exit(1);
}

productServer?.close();
removeReversePort(serial, productPort);

console.log(
  JSON.stringify({
    device: serial,
    avd,
    apk,
    package: packageName,
    receiver: receiverComponent,
    productHost,
    productName,
    roomId,
    chatId: chatHex,
    message,
    diagnosisVerified: expectDiagnosis,
    customRendererVerified: expectCustomRenderer,
    productUrl,
    workerUrl,
    worker,
    report: expectDiagnosis ? reportPath : undefined,
    screenshot,
    verified: true,
  }),
);

function sendDebugHooks(extras) {
  const result = sendBroadcast(serial, {
    action: DEBUG_ACTION,
    component: receiverComponent,
    extras,
  });
  if (result.error) {
    throw new Error(
      `The debug broadcast was rejected: ${result.error}\n${receiverHint}`,
    );
  }
  return result;
}

async function awaitHookAck(ack, timeoutMs = TIMEOUTS.ack) {
  try {
    return await waitForLogcatMessage(serial, {
      tags: [E2E_TAG],
      marker: ack,
      timeoutMs,
      errorTag: E2E_TAG,
    });
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    throw new Error(`${reason}\n${receiverHint}`);
  }
}

function chatMessageWatermark() {
  const query = `SELECT COALESCE(MAX(timestamp), 0) FROM chat_messages WHERE chatId = X'${chatHex}'`;
  try {
    return Number(runAsSqlite(serial, packageName, DATABASE, query).trim()) || 0;
  } catch {
    return 0;
  }
}

function waitForChatMessage(prefix, after, timeoutMs = TIMEOUTS.chatMessage) {
  const query = `SELECT hex(searchableContent) FROM chat_messages WHERE chatId = X'${chatHex}' AND timestamp > ${after} ORDER BY timestamp DESC`;
  return waitFor(
    () => {
      const rows = decodeSqliteHexRows(
        runAsSqlite(serial, packageName, DATABASE, query),
      );
      return rows.find((row) => row.startsWith(prefix));
    },
    {
      timeoutMs,
      intervalMs: 1_000,
      message: () =>
        `Timed out after ${timeoutMs}ms waiting for a chat message starting with ${JSON.stringify(prefix)} in chat ${chatHex} (${DATABASE})`,
    },
  );
}

/** `searchableContent` is indexed for search; fail loudly if it is a preview. */
function assertNotTruncated(report) {
  if (!/\*\*\d+ success · \d+ failed\*\*/.test(report)) {
    throw new Error(
      `The chat ${chatHex} row carries no "N success · M failed" summary; decode the content BLOB the way ChatMessageUiMapper does before trusting this run:\n${report}`,
    );
  }
}
