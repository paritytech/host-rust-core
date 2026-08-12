import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { encodeWireMessage, VersionedHostAccountGetRequest } from "@parity/truapi";
import * as W from "@parity/truapi/wire-table";
import { Window } from "happy-dom";

import { createInAppDebugger } from "./in-app.js";

function frameBytes(id: number, value: number[] = [0]): Uint8Array {
  const r = encodeWireMessage({
    requestId: "p:1",
    payload: { id, value: new Uint8Array(value) },
  });
  if (r.isErr()) throw r.error;
  return r.value;
}

/** A real, decodable account-get request wire message (non-sensitive). */
function accountGetRequestBytes(): Uint8Array {
  const value = VersionedHostAccountGetRequest.enc({
    tag: "V1",
    value: {
      productAccountId: {
        dotNsIdentifier: "alice.dot",
        derivationIndex: { tag: "Index", value: 0 },
      },
    },
  });
  const r = encodeWireMessage({
    requestId: "p:1",
    payload: { id: W.ACCOUNT_GET_ACCOUNT.request, value },
  });
  if (r.isErr()) throw r.error;
  return r.value;
}

describe("createInAppDebugger", () => {
  // The mount is a real interactive panel now (querySelector, dataset, event
  // listeners), so it needs a real DOM rather than a stand-in.
  /* eslint-disable @typescript-eslint/no-explicit-any -- install a DOM global */
  const g = globalThis as any;
  const original = g.document;
  let win: Window;
  beforeAll(() => {
    win = new Window();
    g.document = win.document;
  });
  afterAll(() => {
    g.document = original;
  });
  /* eslint-enable @typescript-eslint/no-explicit-any */

  /** A detached container to mount into. */
  const container = (): HTMLElement =>
    win.document.createElement("div") as unknown as HTMLElement;

  test("feeds frames in-process and decodes by default", () => {
    const dbg = createInAppDebugger(); // decode ON by default (dev-only tool)

    // Two frames of one op, fed exactly as dotli's tap would (raw SCALE bytes).
    // The request leg carries a real, decodable account-get payload.
    dbg.handleFrame("shop.dot", "out", accountGetRequestBytes());
    dbg.handleFrame("shop.dot", "in", frameBytes(W.ACCOUNT_GET_ACCOUNT.response));

    expect(dbg.session.traceEngine.traces()).toHaveLength(1);
    expect(dbg.session.decodeValues).toBe(true); // decodes by default

    // The drill-down surfaces the decoded value.
    const detail = dbg.session.frameDetail("p:1", 0, "shop.dot");
    expect(detail?.kind).toBe("decoded");

    const el = container();
    const dispose = dbg.mount(el);
    // Rendered by the shared renderer — the method resolved via the wire table.
    expect(el.querySelector(".ins-list")?.innerHTML).toContain(
      "account.getAccount",
    );
    dispose();
    expect(el.children).toHaveLength(0);
  });

  test("a formerly-sensitive op is no longer special-cased (never redacted)", () => {
    const dbg = createInAppDebugger();
    dbg.handleFrame("shop.dot", "out", frameBytes(W.SIGNING_SIGN_RAW.request, [1, 2]));
    dbg.handleFrame("shop.dot", "in", frameBytes(W.SIGNING_SIGN_RAW.response));
    const view = dbg.session.traceEngine.traces()[0];
    expect(view).toBeDefined();
    // No denylist: the drill-down either decodes or falls back to bytes, but
    // never returns the old "redacted" state.
    const detail = dbg.session.frameDetail("p:1", 0, "shop.dot");
    expect(["decoded", "bytes"]).toContain(detail?.kind);
    expect(detail?.kind).not.toBe("redacted");
  });

  test("decodeValues:false keeps the mount payload-blind (bytes only)", () => {
    const dbg = createInAppDebugger({ decodeValues: false });
    dbg.handleFrame("shop.dot", "out", accountGetRequestBytes());
    expect(dbg.session.decodeValues).toBe(false);
    expect(dbg.session.frameDetail("p:1", 0, "shop.dot")?.kind).toBe("bytes");
  });

  test("the mount renders the full inspector chrome, not a bare list", () => {
    const dbg = createInAppDebugger();
    dbg.handleFrame("shop.dot", "out", accountGetRequestBytes());
    dbg.handleFrame("shop.dot", "in", frameBytes(W.ACCOUNT_GET_ACCOUNT.response));

    const el = container();
    const dispose = dbg.mount(el);

    // The pieces that made the standalone look like a Network tab and were
    // absent here: a top bar with filter + sort, the aggregate strip, the
    // list/detail split, and a status bar.
    for (const selector of [
      ".ins-top",
      ".ins-filter",
      ".ins-sort",
      ".ins-summary",
      ".ins-body",
      ".ins-list",
      ".ins-split",
      ".ins-detail",
      ".ins-status",
    ]) {
      expect(el.querySelector(selector)).not.toBeNull();
    }
    // The strip reports real aggregates rather than a placeholder.
    expect(el.querySelector(".ins-summary")?.innerHTML).toContain("ops");
    expect(el.querySelector(".ins-summary")?.className).not.toContain("empty");

    dispose();
  });

  test("selecting an operation opens its frames in the detail pane", () => {
    const dbg = createInAppDebugger();
    dbg.handleFrame("shop.dot", "out", accountGetRequestBytes());
    dbg.handleFrame("shop.dot", "in", frameBytes(W.ACCOUNT_GET_ACCOUNT.response));

    const el = container();
    const dispose = dbg.mount(el);

    const detail = el.querySelector(".ins-detail");
    expect(detail?.innerHTML).toContain("Select an operation");

    const row = el.querySelector<HTMLElement>(".td-op");
    expect(row).not.toBeNull();
    row?.click();

    // The drill-down replaces the placeholder, and the row reads as selected.
    expect(detail?.innerHTML).not.toContain("Select an operation");
    expect(detail?.innerHTML).toContain("account.getAccount");
    expect(el.querySelector(".td-op.selected")).not.toBeNull();

    dispose();
  });

  test("the filter narrows the operation list", () => {
    const dbg = createInAppDebugger();
    dbg.handleFrame("shop.dot", "out", accountGetRequestBytes());
    dbg.handleFrame("shop.dot", "in", frameBytes(W.ACCOUNT_GET_ACCOUNT.response));

    const el = container();
    const dispose = dbg.mount(el);
    expect(el.querySelectorAll(".td-op")).toHaveLength(1);

    const filter = el.querySelector<HTMLInputElement>(".ins-filter");
    expect(filter).not.toBeNull();
    if (filter !== null) {
      filter.value = "signing.signRaw";
      filter.dispatchEvent(new win.Event("input") as unknown as Event);
    }
    expect(el.querySelectorAll(".td-op")).toHaveLength(0);
    expect(el.querySelector(".ins-list")?.innerHTML).toContain("no operations");

    dispose();
  });
});
