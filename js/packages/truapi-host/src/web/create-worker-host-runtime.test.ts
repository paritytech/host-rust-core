// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: MIT
/**
 * Tests for how a host is told to dial the wire debugger: the `debugger` option,
 * the build-time default, the production gate, and the `__truapi.debugger`
 * console. Lives beside the file it covers - these were in
 * `worker-provider.test.ts`, where a reviewer looking for them reasonably
 * concluded the precedence was untested.
 */
import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { Window } from "happy-dom";

import {
  productionReason,
  resolveDebuggerEnablement,
} from "./create-worker-host-runtime.js";
import {
  FakeWorker,
  lastMessageOfKind,
  readyRuntime,
} from "./worker-test-harness.js";

describe("debugger enablement reporting", () => {
  // Under `bun test` `import.meta.env.DEV` reads undefined, so the live path
  // always takes its production branch - which is the one asserted here.
  const capturingInfo = async (
    run: () => Promise<unknown>,
  ): Promise<string[]> => {
    const logged: string[] = [];
    const info = console.info;
    console.info = (...args: unknown[]) => {
      logged.push(args.map(String).join(" "));
    };
    try {
      await run();
    } finally {
      console.info = info;
    }
    return logged;
  };

  // Nothing was asked for, so there is nothing to report and the line would be
  // pure noise. `readyRuntime` passes no `debugger` option, and under `bun test`
  // there is no build value either.
  it("stays silent in a production build nobody asked to debug", async () => {
    const worker = new FakeWorker();
    const logged = await capturingInfo(() => readyRuntime(worker));
    expect(logged.filter((l) => l.includes("wire debugger"))).toHaveLength(0);
  });

  // The counterpart, and the regression this pair exists for. Silence when a dial
  // WAS configured is design doc §9's named failure: the easiest way to reach it
  // is to copy the build command and drop `NODE_ENV=development`, and the result
  // is an empty board with no console line and no error.
  it("says so once when a dial was configured but the build compiled it out", async () => {
    const worker = new FakeWorker();
    const logged = await capturingInfo(() =>
      readyRuntime(worker, { debugger: "ws://127.0.0.1:9231" }),
    );
    const line = logged.find((l) => l.includes("wire debugger"));
    expect(line).toBeDefined();
    // Must not assert a cause it cannot know: a production build and a bundler
    // that never substituted the token both leave the condition false.
    expect(line).toContain("did not resolve true");
  });

  // The tap is armed for the whole dev session, not only while a URL is set: the
  // worker decides a core's `debugEmit` once, when the core is built, so a session
  // that starts detached must still arm or a later attach() reaches nothing. In a
  // production build it must stay false, or a core would carry a live sink.
  // Asserted with a dial CONFIGURED, which is the only input that can fail. A
  // build that carries `VITE_TRUAPI_DEBUGGER_URL`, or a host that passes
  // `debugger:` unconditionally rather than behind its own dev flag, lands on
  // `production-build-configured` - and deriving the flag as
  // `reason !== "production-build"` armed exactly those. `withDebugTap` then adds
  // `debugEmit`, which is what makes the Rust side install its `DebugSink`, and
  // `case "setDebuggerUrl"` guards only on this flag, so a single
  // `__truapi.debugger.attach()` streamed decoded frames out of a production
  // bundle. Passing no option cannot see that: it is the one input where both
  // production reasons agree.
  it("never arms the tap when the build refuses, even with a dial configured", async () => {
    const worker = new FakeWorker();
    await readyRuntime(worker, { debugger: "ws://127.0.0.1:9231" });
    const init = worker.messages.find((m) => m.kind === "init");
    expect(init).toMatchObject({ debugTapArmed: false, debuggerUrl: null });
  });

  it("never arms the tap when nothing was configured either", async () => {
    const worker = new FakeWorker();
    await readyRuntime(worker);
    const init = worker.messages.find((m) => m.kind === "init");
    expect(init).toMatchObject({ debugTapArmed: false, debuggerUrl: null });
  });
});

// The dev-build branch, which the suite above cannot reach: it gates on
// `import.meta.env.DEV`, a token a bundler substitutes and `bun test` leaves
// undefined, so the live call always takes the production path here. The pure
// seam is where the precedence can actually be asserted.
describe("debugger switch precedence", () => {
  const BUILD = "ws://127.0.0.1:9231";

  it("dials the host's option over the build's value", () => {
    expect(resolveDebuggerEnablement("ws://127.0.0.1:9300", BUILD)).toEqual({
      url: "ws://127.0.0.1:9300",
      reason: "enabled-from-option",
    });
  });

  // Omitting the field is how a host says "whatever you were built with", which
  // is what makes `make debugger` work with nothing to switch on.
  it("falls back to the build's value when the host passes nothing", () => {
    expect(resolveDebuggerEnablement(undefined, BUILD)).toEqual({
      url: BUILD,
      reason: "enabled-from-build",
    });
  });

  // The case that is easy to fold in with "omitted". If null fell through to the
  // build, a host compiled with a URL could not refuse the dial short of being
  // rebuilt - so a host has no way to turn the tap off for its own users.
  it("treats an explicit null or empty string as OFF, beating the build", () => {
    expect(resolveDebuggerEnablement(null, BUILD)).toEqual({
      url: null,
      reason: "not-configured",
    });
    expect(resolveDebuggerEnablement("", BUILD)).toEqual({
      url: null,
      reason: "not-configured",
    });
  });

  it("is off with neither switch set", () => {
    expect(resolveDebuggerEnablement(undefined, null)).toEqual({
      url: null,
      reason: "not-configured",
    });
  });
});

describe("productionReason", () => {
  const URL = "ws://127.0.0.1:9231";

  it("is silent only when nothing asked for a dial", () => {
    expect(productionReason(undefined, null)).toBe("production-build");
    expect(productionReason(null, null)).toBe("production-build");
    expect(productionReason("", null)).toBe("production-build");
  });

  // The reviewer's scenario, and the half a test can otherwise never reach: the
  // env var IS substituted into a production bundle, so a build made with it but
  // without `NODE_ENV=development` is readable here and must not go quiet.
  it("reports a build-carried URL in a production build", () => {
    expect(productionReason(undefined, URL)).toBe(
      "production-build-configured",
    );
  });

  it("reports a host that asked, whatever the build carries", () => {
    expect(productionReason(URL, null)).toBe("production-build-configured");
  });
});

describe("the dial indicator", () => {
  // A real DOM, not a stand-in: the badge touches createElement/appendChild/
  // getElementById/remove, and a hand-rolled fake would be asserting the fake.
  const g = globalThis as unknown as { document?: unknown };
  let hadDocument = false;
  let previousDocument: unknown;

  beforeEach(() => {
    hadDocument = Object.prototype.hasOwnProperty.call(g, "document");
    previousDocument = g.document;
    g.document = new Window().document;
  });

  afterEach(() => {
    if (hadDocument) g.document = previousDocument;
    else delete g.document;
  });

  const el = (): { textContent: string | null } | null =>
    (
      globalThis.document as unknown as {
        getElementById(id: string): { textContent: string | null } | null;
      }
    ).getElementById("truapi-debugger-indicator");

  const silently = (run: () => void): void => {
    const info = console.info;
    console.info = () => {};
    try {
      run();
    } finally {
      console.info = info;
    }
  };

  afterEach(() => {
    silently(() => {
      (
        globalThis as unknown as { __truapi: { debugger: { detach(): void } } }
      ).__truapi.debugger.detach();
    });
  });

  // A console line scrolls away; a tap left on from an earlier session is then
  // invisible for the rest of the day. Default-on, because the failure being
  // prevented is a host forgetting to render one.
  it("appears on attach and names the endpoint", () => {
    silently(() => {
      (
        globalThis as unknown as {
          __truapi: { debugger: { attach(u: string): void } };
        }
      ).__truapi.debugger.attach("ws://127.0.0.1:9231");
    });
    expect(el()?.textContent).toContain("ws://127.0.0.1:9231");
  });

  it("goes away on detach", () => {
    const api = (
      globalThis as unknown as {
        __truapi: { debugger: { attach(u: string): void; detach(): void } };
      }
    ).__truapi.debugger;
    silently(() => {
      api.attach("ws://127.0.0.1:9231");
      api.detach();
    });
    expect(el()).toBeNull();
  });

  // Never a reason for a host to fail to start: `document` is absent in a worker
  // or under plain Node, and the badge must simply not render there.
  // Never a reason for a host to fail to start: `document` is absent in a worker
  // and under plain Node, and the badge must simply not render there.
  it("is inert where there is no document", () => {
    delete g.document;
    expect(() =>
      silently(() => {
        (
          globalThis as unknown as {
            __truapi: { debugger: { attach(u: string): void } };
          }
        ).__truapi.debugger.attach("ws://127.0.0.1:9231");
      }),
    ).not.toThrow();
  });
});

describe("__truapi.debugger", () => {
  const devConsole = (): {
    attach(url: string): void;
    detach(): void;
    status(): string | null;
  } => {
    const g = globalThis as unknown as {
      __truapi?: { debugger: ReturnType<typeof devConsole> };
    };
    const api = g.__truapi?.debugger;
    if (!api) throw new Error("__truapi.debugger was not published");
    return api;
  };

  const silently = (run: () => void): void => {
    const info = console.info;
    console.info = () => {};
    try {
      run();
    } finally {
      console.info = info;
    }
  };

  afterEach(() => {
    silently(() => {
      devConsole().detach();
    });
  });

  // The whole point of the console over a storage key: repointing a host that is
  // already running, with no reload and no per-origin key to get wrong.
  it("repoints a live runtime without a reload", async () => {
    const worker = new FakeWorker();
    await readyRuntime(worker);
    silently(() => {
      devConsole().attach("ws://127.0.0.1:9300");
    });
    expect(lastMessageOfKind(worker, "setDebuggerUrl")).toEqual({
      kind: "setDebuggerUrl",
      url: "ws://127.0.0.1:9300",
    });
    expect(devConsole().status()).toBe("ws://127.0.0.1:9300");
  });

  // Detach must reach the worker as an explicit null rather than simply going
  // quiet on the main thread: the link owns a socket and a reconnect timer, and
  // only the worker can close them.
  it("detaches by sending null, and forgets the url", async () => {
    const worker = new FakeWorker();
    await readyRuntime(worker);
    silently(() => {
      devConsole().attach("ws://127.0.0.1:9300");
      devConsole().detach();
    });
    expect(lastMessageOfKind(worker, "setDebuggerUrl")).toEqual({
      kind: "setDebuggerUrl",
      url: null,
    });
    expect(devConsole().status()).toBeNull();
  });

  // A host that rebuilds its runtime mid-session (a reset, a product swap) would
  // otherwise stop streaming with nothing said, which reads as the debugger
  // dropping the connection rather than the host replacing its runtime.
  it("replays the attached url onto a runtime created afterwards", async () => {
    silently(() => {
      devConsole().attach("ws://127.0.0.1:9300");
    });
    const worker = new FakeWorker();
    await readyRuntime(worker);
    expect(lastMessageOfKind(worker, "setDebuggerUrl")).toEqual({
      kind: "setDebuggerUrl",
      url: "ws://127.0.0.1:9300",
    });
  });

  // Called directly, not through the console: dispose() already unregisters the
  // runtime from the fan-out, so routing this through attach() would pass with or
  // without the guard. `setDebuggerUrl` is a public method on the runtime, so a
  // host can reach a disposed one on its own, and its worker is gone by then.
  it("does not post to a disposed runtime", async () => {
    const worker = new FakeWorker();
    const runtime = await readyRuntime(worker);
    runtime.dispose();
    const before = worker.messages.length;
    runtime.setDebuggerUrl("ws://127.0.0.1:9300");
    expect(worker.messages.length).toBe(before);
  });
});
