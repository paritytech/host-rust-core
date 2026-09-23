// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: MIT
/**
 * Tests for how a host is told to dial the wire debugger: the `debugger` option,
 * the build-time default, the production gate, and the dial indicator. Lives
 * beside the file it covers - these were in
 * `worker-provider.test.ts`, where a reviewer looking for them reasonably
 * concluded the precedence was untested.
 */
import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { Window } from "happy-dom";

import {
  installDebuggerDial,
  productionReason,
  releaseDebuggerDial,
  resolveDebuggerEnablement,
} from "./create-worker-host-runtime.js";
import {
  asWorker,
  FakeWorker,
  hostConfigFromRuntimeConfig,
  readyRuntime,
  runtimeConfig,
} from "./worker-test-harness.js";
import { makeHostCallbacks } from "../test-support.js";
import { createWebWorkerPairingHostRuntime } from "./index.js";

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

    // The log line alone would pass while the worker still got a URL. `init`
    // carrying null is what actually keeps a core from building a tap, and a
    // configured dial is the only input that can tell the two apart: with no
    // option and no build value, a broken gate looks identical to a working one.
    const init = worker.messages.find((m) => m.kind === "init");
    expect(init).toMatchObject({ debuggerUrl: null });
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
  // Same reasoning as the null case, for the value a host that is not writing
  // TypeScript actually produces. `wanted && url` yields `false`, and falling
  // through to the build there turns the tap on for a host that asked for it
  // off, which is the opposite of what the option is for.
  it("treats any non-URL the host passed as OFF, beating the build", () => {
    expect(
      resolveDebuggerEnablement(false as unknown as string, BUILD),
    ).toEqual({
      url: null,
      reason: "not-configured",
    });
  });

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

  // §6: the tap forwards frames verbatim, payloads included, so a target off this
  // machine is refused rather than dialled. The worker already builds an inert
  // link for one, which is exactly why resolving it as enabled is the dangerous
  // half: the host would log and badge an endpoint that never carries a frame.
  it("refuses a target that is not loopback ws://, from either switch", () => {
    for (const hostile of [
      "ws://evil.example.com:9231",
      "wss://127.0.0.1:9231",
      "ws://127.0.0.1.evil.com:9231",
      "http://127.0.0.1:9231",
    ]) {
      expect(resolveDebuggerEnablement(hostile, null)).toEqual({
        url: null,
        reason: "refused-not-loopback",
      });
      expect(resolveDebuggerEnablement(undefined, hostile)).toEqual({
        url: null,
        reason: "refused-not-loopback",
      });
    }
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

  // The one cell where the two sources disagree, and the only one that can tell
  // this apart from an OR. A host that passed `debugger: null` refused, so the
  // build value is not consulted: reporting it as configured advises a dev-mode
  // rebuild that `resolveDebuggerEnablement` would still resolve to
  // `not-configured`.
  it("stays silent for a host that refused, whatever the build carries", () => {
    expect(productionReason(null, URL)).toBe("production-build");
    expect(resolveDebuggerEnablement(null, URL).reason).toBe("not-configured");
  });
});

// What a resolved dial actually does, which is the half the suites above cannot
// reach: they go through the live `import.meta.env.DEV` gate, so `url` is always
// null there and every dev-build behaviour is invisible. `installDebuggerDial`
// takes the enablement instead of resolving it, so the resolved case is
// reachable here.
describe("putting a dial into service", () => {
  const ENDPOINT = "ws://127.0.0.1:9231";
  const OTHER = "ws://127.0.0.1:9300";

  // A real DOM, not a stand-in: the badge touches createElement/appendChild/
  // getElementById/remove, and a hand-rolled fake would be asserting the fake.
  const g = globalThis as unknown as { document?: unknown };
  let had = false;
  let previous: unknown;
  let owners: object[] = [];

  beforeEach(() => {
    had = Object.prototype.hasOwnProperty.call(g, "document");
    previous = g.document;
    g.document = new Window().document;
    owners = [];
  });
  afterEach(() => {
    // The dial registry is module state and outlives this document, so a dial
    // left in it would paint into the next test's page.
    for (const owner of owners) releaseDebuggerDial(owner);
    if (had) g.document = previous;
    else delete g.document;
  });

  /** A stand-in for one worker runtime, released when the test ends. */
  const newOwner = (): object => {
    const owner = {};
    owners.push(owner);
    return owner;
  };

  /** Install a dial for a fresh owner. */
  const dial = (url: string | null, indicator?: boolean): object => {
    const owner = newOwner();
    installDebuggerDial(
      owner,
      { url, reason: url === null ? "not-configured" : "enabled-from-option" },
      indicator,
    );
    return owner;
  };

  const badge = (): { textContent: string | null } | null =>
    (
      globalThis.document as unknown as {
        getElementById(id: string): { textContent: string | null } | null;
      }
    ).getElementById("truapi-debugger-indicator");

  // The live wiring, asserted as one thing. A runtime that resolves a dial has
  // to report it, show it (PG's requirement: a host streaming frames says so
  // where you can see it, not only in a console line that scrolls away), and
  // hand that same URL to the worker, or the host and what it is doing part
  // company. Dropping any one of the three leaves the other two looking fine.
  it("reports the endpoint, shows it, and hands it to the worker", () => {
    const logged: string[] = [];
    const info = console.info;
    console.info = (...args: unknown[]) => {
      logged.push(args.map(String).join(" "));
    };
    const owner = newOwner();
    let forWorker: string | null;
    try {
      forWorker = installDebuggerDial(
        owner,
        { url: ENDPOINT, reason: "enabled-from-option" },
        undefined,
      );
    } finally {
      console.info = info;
    }

    expect(forWorker).toBe(ENDPOINT);
    expect(logged.filter((l) => l.includes(ENDPOINT))).toHaveLength(1);
    expect(badge()?.textContent).toContain(ENDPOINT);
  });

  // The null case is every production build, and any dev build nobody gave a
  // dial: there is nothing to announce, so nothing may be painted.
  it("paints nothing without a dial", () => {
    dial(null);
    expect(badge()).toBeNull();
  });

  // Only for a host that renders its own signal - the guarantee is that a tap is
  // never invisible, not that this particular badge is the one used.
  it("can be suppressed by the host", () => {
    dial(ENDPOINT, false);
    expect(badge()).toBeNull();
  });

  // An embedder with one worker runtime per product surface gives only some of
  // them a dial. The badge is a single node at a fixed id, so a runtime with
  // nothing to announce must leave it alone rather than take down the signal
  // that another runtime's tap is still streaming.
  it("leaves a badge another runtime's dial put there alone", () => {
    dial(ENDPOINT);
    dial(null);
    dial(OTHER, false);
    expect(badge()?.textContent).toContain(ENDPOINT);
  });

  // Two taps are two places frames are going, and a badge naming one of them
  // reads as the whole story.
  it("names every live endpoint", () => {
    dial(ENDPOINT);
    dial(OTHER);
    expect(badge()?.textContent).toContain(ENDPOINT);
    expect(badge()?.textContent).toContain(OTHER);
  });

  // Nothing streams once the runtimes are gone, and a badge naming an endpoint
  // no frame reaches is as misleading as a silent tap.
  it("paints nothing once the last dial is released", () => {
    const first = dial(ENDPOINT);
    const second = dial(OTHER);
    releaseDebuggerDial(first);
    expect(badge()?.textContent).not.toContain(ENDPOINT);
    releaseDebuggerDial(second);
    expect(badge()).toBeNull();
  });

  // A runtime created from a `<head>` script resolves its dial before there is a
  // body to mount on. Returning alone would leave the tap live and the badge
  // permanently absent, which is the one case it exists for.
  it("paints once the document body arrives", () => {
    const withBody = globalThis.document;
    let pending: (() => void) | null = null;
    g.document = {
      body: null,
      addEventListener: (name: string, fn: () => void) => {
        if (name === "DOMContentLoaded") pending = fn;
      },
      getElementById: () => null,
    };

    dial(ENDPOINT);
    expect(pending).not.toBeNull();

    g.document = withBody;
    pending!();
    expect(badge()?.textContent).toContain(ENDPOINT);
  });

  // Never a reason for a host to fail to start: `document` is absent in a worker
  // and under plain Node.
  it("is inert where there is no document", () => {
    delete g.document;
    expect(() => dial(ENDPOINT)).not.toThrow();
  });
});

// The runtime resolves its own dial behind `import.meta.env.DEV`, which reads as
// undefined under the test runner - so a runtime-driven badge assertion passes
// whatever the code does. Turning the gate on is what gives these two something
// to observe; without it both would hold against a runtime that never releases.
describe("a runtime whose worker never loads", () => {
  const ENDPOINT = "ws://127.0.0.1:9231";
  const env = (import.meta as unknown as { env: Record<string, unknown> }).env;
  const g = globalThis as unknown as { document?: unknown };
  let hadDev = false;
  let previousDev: unknown;
  let hadDoc = false;
  let previousDoc: unknown;

  beforeEach(() => {
    hadDev = "DEV" in env;
    previousDev = env.DEV;
    env.DEV = true;
    hadDoc = Object.prototype.hasOwnProperty.call(g, "document");
    previousDoc = g.document;
    g.document = new Window().document;
  });
  afterEach(() => {
    if (hadDev) env.DEV = previousDev;
    else delete env.DEV;
    if (hadDoc) g.document = previousDoc;
    else delete g.document;
  });

  const badge = (): { textContent: string | null } | null =>
    (
      globalThis.document as unknown as {
        getElementById(id: string): { textContent: string | null } | null;
      }
    ).getElementById("truapi-debugger-indicator");

  const startWithDial = (worker: FakeWorker): Promise<unknown> => {
    const started = createWebWorkerPairingHostRuntime(
      asWorker(worker),
      makeHostCallbacks(),
      {
        hostConfig: hostConfigFromRuntimeConfig(runtimeConfig()),
        debugger: ENDPOINT,
      },
    );
    worker.emit({ kind: "loaded" });
    return started;
  };

  // Nothing streams for a worker that never came up, so a badge naming its
  // endpoint is the silent-tap failure read backwards: it says frames are
  // leaving for somewhere nothing is sending.
  it("takes its dial out of service when init reports a fatal error", async () => {
    const worker = new FakeWorker();
    const started = startWithDial(worker);
    expect(badge()?.textContent).toContain(ENDPOINT);

    worker.emit({ kind: "fatalError", error: "boom" });
    await expect(started).rejects.toThrow("boom");
    expect(badge()).toBeNull();
  });

  // The same for the path where the worker script itself fails to load, which
  // reaches the reject through a different listener.
  it("takes its dial out of service when the worker errors", async () => {
    const worker = new FakeWorker();
    const started = startWithDial(worker);
    worker.emitError("no such script");
    await expect(started).rejects.toThrow("no such script");
    expect(badge()).toBeNull();
  });

  // The other half of the same decision: releasing for every `cleanupInit`
  // caller rather than only the failing ones would take the badge down on the
  // runtime that is about to start streaming.
  it("keeps its dial once the worker is ready", async () => {
    const worker = new FakeWorker();
    const started = startWithDial(worker);
    worker.emit({ kind: "ready" });
    const runtime = await started;
    expect(badge()?.textContent).toContain(ENDPOINT);
    releaseDebuggerDial(runtime as object);
  });
});
