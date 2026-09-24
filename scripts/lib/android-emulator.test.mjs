import assert from "node:assert/strict";
import test from "node:test";

import {
  chatIdHex,
  decodeSqliteHexRows,
  findLogcatError,
  findLogcatMessage,
  isAdbUnhealthy,
  parseAvdList,
  parseBroadcastResult,
  parseDeviceList,
  parseLogcatLine,
  selectDevice,
  shellCommand,
  shellQuote,
} from "./android-emulator.mjs";

test("the chat id hex is the uppercase UTF-8 encoding of that string", () => {
  const hex = chatIdHex("truapi-playground.dot", "truapi-playground");
  assert.equal(hex, hex.toUpperCase());
  assert.equal(
    Buffer.from(hex, "hex").toString("utf8"),
    "ChatExtension:truapi-playground.dot:truapi-playground",
  );
  assert.equal(hex.slice(0, 28), "43686174457874656E73696F6E3A");
});

test("a room id keeps its own colon separator", () => {
  assert.equal(
    Buffer.from(chatIdHex("a.dot", "room:with:colons"), "hex").toString("utf8"),
    "ChatExtension:a.dot:room:with:colons",
  );
});

const deviceList = `List of devices attached
emulator-5554	offline
emulator-5556	device
`;

test("adb devices parses serial and state, skipping the header", () => {
  assert.deepEqual(parseDeviceList(deviceList), [
    { serial: "emulator-5554", state: "offline" },
    { serial: "emulator-5556", state: "device" },
  ]);
});

test("daemon chatter is not mistaken for a device", () => {
  const noisy = `* daemon not running; starting now at tcp:5037
* daemon started successfully
List of devices attached
emulator-5554	device
`;
  assert.deepEqual(parseDeviceList(noisy), [
    { serial: "emulator-5554", state: "device" },
  ]);
});

test("the default device is the first online one", () => {
  assert.equal(selectDevice(deviceList)?.serial, "emulator-5556");
});

test("a requested device must also be online", () => {
  assert.equal(selectDevice(deviceList, "emulator-5556")?.serial, "emulator-5556");
  assert.equal(selectDevice(deviceList, "emulator-5554"), undefined);
  assert.equal(selectDevice(deviceList, "emulator-9999"), undefined);
});

test("a wedged adb server is recognised as recoverable", () => {
  assert.equal(
    isAdbUnhealthy({ status: 1, stderr: "error: device offline" }),
    true,
  );
  assert.equal(
    isAdbUnhealthy({ status: 1, stderr: "adb: error: protocol fault" }),
    true,
  );
  assert.equal(isAdbUnhealthy({ status: null, timedOut: true }), true);
});

test("an ordinary command failure is not an adb health problem", () => {
  assert.equal(
    isAdbUnhealthy({ status: 1, stderr: "run-as: unknown package: foo" }),
    false,
  );
  assert.equal(isAdbUnhealthy({ status: 0, stdout: "device offline" }), false);
});

const logcat = `--------- beginning of main
09-23 18:44:01.123  4711  4733 D truapi.core: truapi.ws_bridge.connection_open: 127.0.0.1:41234
09-23 18:44:02.001  4711  4733 I truapi.e2e: seed_identity done
09-23 18:44:03.500  4711  4733 W truapi.e2e: error worker_url unreachable
`;

test("threadtime lines split into level, tag and message", () => {
  assert.deepEqual(
    parseLogcatLine(
      "09-23 18:44:02.001  4711  4733 I truapi.e2e: seed_identity done",
    ),
    { level: "I", tag: "truapi.e2e", message: "seed_identity done" },
  );
});

test("buffer banners and continuations are ignored", () => {
  assert.equal(parseLogcatLine("--------- beginning of main"), undefined);
  assert.equal(parseLogcatLine("    at some.Frame(File.kt:12)"), undefined);
  assert.equal(parseLogcatLine(""), undefined);
});

test("a marker is found anywhere in the message", () => {
  assert.equal(
    findLogcatMessage(logcat, "truapi.ws_bridge.connection_open")?.tag,
    "truapi.core",
  );
  assert.equal(findLogcatMessage(logcat, "custom_renderer_update"), undefined);
});

test("hook errors are detected only under their own tag", () => {
  assert.equal(
    findLogcatError(logcat, "truapi.e2e")?.message,
    "error worker_url unreachable",
  );
  assert.equal(findLogcatError(logcat, "truapi.core"), undefined);
});

test("the hook error format is recognised", () => {
  const line =
    "09-23 18:44:05.000  4711  4733 W truapi.e2e: error seed_identity keystore locked";
  assert.equal(
    findLogcatError(line, "truapi.e2e")?.message,
    "error seed_identity keystore locked",
  );
});

test("a message merely containing the word error is not a failure", () => {
  const line =
    "09-23 18:44:04.000  4711  4733 I truapi.e2e: message delivered after error recovery";
  assert.equal(findLogcatError(line, "truapi.e2e"), undefined);
});

test("device-side tokens are quoted for sh", () => {
  assert.equal(shellQuote("!diagnose"), "'!diagnose'");
  assert.equal(shellQuote("it's"), "'it'\\''s'");
  assert.equal(
    shellCommand(["am", "broadcast", "--es", "message", "hello world"]),
    "'am' 'broadcast' '--es' 'message' 'hello world'",
  );
});

test("hex rows decode back to multi-line markdown", () => {
  const report = "## Truapi Chat Diagnosis\n\n**3 success · 0 failed**";
  const output = `${Buffer.from(report, "utf8").toString("hex")}\n`;
  assert.deepEqual(decodeSqliteHexRows(output), [report]);
});

test("non-hex noise in the sqlite output is dropped", () => {
  assert.deepEqual(decodeSqliteHexRows("Error: no such table\n4869\n"), ["Hi"]);
});

test("a delivered broadcast reports no error", () => {
  assert.deepEqual(
    parseBroadcastResult(
      "Broadcasting: Intent { act=io.paritytech.polkadotapp.debug.E2E }\nBroadcast completed: result=0\n",
    ),
    { error: undefined },
  );
  assert.deepEqual(parseBroadcastResult(""), { error: undefined });
});

test("a bad component surfaces as a broadcast error", () => {
  assert.match(
    parseBroadcastResult(
      "Error: Bad component name: com.example.polkadot.debug/NoSuchReceiver\n",
    ).error,
    /Bad component name/,
  );
});

test("avd names ignore tooling chatter", () => {
  assert.deepEqual(
    parseAvdList("INFO    | Storing crashdata\ntruapi-chat-e2e\nPixel 7 API 34\n"),
    ["truapi-chat-e2e"],
  );
});
