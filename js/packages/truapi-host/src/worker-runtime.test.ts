import { describe, expect, test } from "bun:test";

import { isLoopbackWsUrl } from "./worker-runtime.js";

/**
 * The gate mirrors the native sink's (`native_debug.rs`) three cases — loopback
 * forms, bracket forms, and non-loopback rejection — and then covers the shapes
 * a string-matching check is normally bypassed by.
 *
 * The one deliberate difference from the Rust side: `WsDebugSink::connect`
 * *resolves* the host and requires every resolved address to be loopback, which
 * closes the "validate one string, dial another" gap. A Web Worker has no
 * resolver, so this checks the hostname the WHATWG parser normalized. That is
 * sound here for the reason the Rust gap needed closing at all: the same `url`
 * string is handed to `new WebSocket(url)`, so the browser resolves exactly what
 * was validated — there is no second, unvalidated string.
 */
describe("isLoopbackWsUrl", () => {
  test("accepts ws:// on every genuine loopback form", () => {
    for (const url of [
      "ws://localhost:9231",
      "ws://127.0.0.1:9231",
      // 127.0.0.0/8 in full, not just 127.0.0.1.
      "ws://127.5.6.7:9231",
      "ws://[::1]:9231",
      // Bracket forms: expanded and IPv4-mapped, both of which the URL parser
      // normalizes to a different string than the one written.
      "ws://[0:0:0:0:0:0:0:1]:9231",
      "ws://[::ffff:127.0.0.1]:9231",
      "ws://[::ffff:7f00:1]:9231",
      // Scheme and host are case-insensitive; a path or query is irrelevant.
      "WS://127.0.0.1:9231",
      "ws://LOCALHOST:9231",
      "ws://127.0.0.1:9231/path?q=1",
    ]) {
      expect(isLoopbackWsUrl(url)).toBe(true);
    }
  });

  test("rejects wss:// — the tap is ws-only, matching the native sink", () => {
    expect(isLoopbackWsUrl("wss://localhost:9231")).toBe(false);
    expect(isLoopbackWsUrl("wss://127.0.0.1:9231")).toBe(false);
    expect(isLoopbackWsUrl("wss://[::1]:9231")).toBe(false);
  });

  test("rejects every non-ws scheme, including ones that parse", () => {
    for (const url of [
      "http://127.0.0.1:9231",
      "https://127.0.0.1:9231",
      "file://127.0.0.1",
      "javascript:alert(1)",
      "not a url",
      "",
    ]) {
      expect(isLoopbackWsUrl(url)).toBe(false);
    }
  });

  test("rejects non-loopback hosts, including the ones that look local", () => {
    for (const url of [
      "ws://192.0.2.1:9231",
      "ws://example.com:9231",
      // A wildcard bind is not loopback: it is reachable from off-machine.
      "ws://0.0.0.0:9231",
      // Private and link-local ranges are still off-machine.
      "ws://10.0.0.1:9231",
      "ws://169.254.169.254:9231",
      // IPv4-mapped *non*-loopback must not ride the ::ffff: prefix in.
      "ws://[::ffff:192.0.2.1]:9231",
      // A trailing dot is a distinct hostname and is not accepted.
      "ws://localhost.:9231",
    ]) {
      expect(isLoopbackWsUrl(url)).toBe(false);
    }
  });

  test("rejects hosts that merely embed a loopback-looking substring", () => {
    for (const url of [
      "ws://localhost.evil.com:9231",
      "ws://127.0.0.1.evil.com:9231",
      // Path and userinfo are not the host: the dial target is `evil.com`.
      "ws://evil.com/127.0.0.1",
      "ws://user:pass@evil.com:9231",
      "ws://127.0.0.1@evil.com:9231",
      // A homoglyph digit does not normalize to an ASCII loopback literal.
      "ws://➀27.0.0.1:9231",
    ]) {
      expect(isLoopbackWsUrl(url)).toBe(false);
    }
  });

  test("accepts alternate integer spellings of 127.0.0.1 — they are loopback", () => {
    // The WHATWG parser normalizes these to `127.0.0.1` before the check, and
    // `new WebSocket(url)` normalizes identically, so accepting them is correct:
    // the socket really does go to loopback. Pinned so a future hand-rolled
    // hostname check cannot quietly start disagreeing with the parser.
    expect(isLoopbackWsUrl("ws://2130706433:9231")).toBe(true);
    expect(isLoopbackWsUrl("ws://0177.0.0.1:9231")).toBe(true);
    expect(isLoopbackWsUrl("ws://0x7f.0.0.1:9231")).toBe(true);
    // The same spellings for a non-loopback address stay rejected.
    expect(isLoopbackWsUrl("ws://3221225985:9231")).toBe(false);
  });

  test("userinfo cannot smuggle a non-loopback dial target", () => {
    // Mirror of the rejection case: here the *host* is loopback and the
    // userinfo is the decoy, so the dial is loopback and the URL is accepted.
    expect(isLoopbackWsUrl("ws://evil.com@127.0.0.1:9231")).toBe(true);
  });
});
