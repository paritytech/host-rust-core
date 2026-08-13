// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: MIT
/**
 * In-app mount: render the inspector from a {@link DebugSession} that lives in
 * the SAME app as the host — no server, no dial-out, no relay. A host running in
 * the page (dotli) feeds each tapped frame via {@link InAppDebugger.handleFrame};
 * {@link InAppDebugger.mount} renders them with the same engine, the same
 * renderers, and the same stylesheet the standalone app uses, decoding every
 * frame by default (dev-only tool).
 *
 * This is the "host and debugger in the same bits" transport: the frames never
 * leave the app, so each browser tab is its own tenant — nothing to host or
 * scope. Browser-only (uses `document`).
 *
 * The standalone app is a thin client over server-rendered fragments; this mount
 * has the session in-process, so it renders the same fragments directly and needs
 * no polling. Everything visible — the summary strip, the operation list, the
 * drill-down — comes from the shared renderers and the shared stylesheet, so the
 * two mounts cannot drift apart.
 *
 * @module
 */

import { createDebugSession, decodeTraceFrames } from "./session.js";
import type { DebugSession, DebugSessionOptions } from "./session.js";
import { wireTraceToView, type TraceView } from "./trace-view.js";
import { renderOperationRow, renderTraceDetail } from "./trace-render.js";
import { detectRetryStorms } from "./retry-storm.js";
import { TRACE_DETAIL_CSS } from "./trace-styles.js";
import {
  INSPECTOR_LAYOUT_CSS,
  INSPECTOR_SHELL_CSS,
} from "./inspector-styles.js";

/** How an operation list is ordered. */
type SortMode = "arrival" | "slowest" | "frames";

/** A same-app debugger: feed it frames, mount its panel. */
export interface InAppDebugger {
  /** The underlying session — grouped traces, inline value decode. */
  readonly session: DebugSession;
  /**
   * Feed one tapped frame: the raw SCALE `ProtocolMessage` bytes, opaque. `dir`
   * is product-vantage (`out` = left the product), matching the standalone tap.
   */
  handleFrame(channelId: string, dir: "in" | "out", frame: Uint8Array): void;
  /**
   * Render a live, self-contained panel into `el` and keep it refreshed; returns
   * a disposer that tears the panel down. Decodes every frame unless the session
   * was created with `decodeValues: false`.
   */
  mount(el: HTMLElement, options?: { refreshMs?: number }): () => void;
}

/** HTML-escape a string for interpolation into the markup this module builds. */
function esc(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** `1.2s` / `340ms`, matching the standalone's tile formatting. */
function formatMs(ms: number): string {
  return ms >= 1000
    ? `${(ms / 1000).toFixed(1)}s`
    : `${String(Math.round(ms))}ms`;
}

/** One metric tile in the aggregate strip. */
function stat(n: string, k: string, cls = ""): string {
  return (
    `<div class="ins-stat${cls === "" ? "" : ` ${cls}`}">` +
    `<span class="n">${esc(n)}</span><span class="k">${esc(k)}</span></div>`
  );
}

/** The aggregate summary strip: the "at a glance" row above the list. */
function renderSummary(views: readonly TraceView[]): string {
  if (views.length === 0) return "waiting for frames…";

  const frames = views.reduce((sum, v) => sum + v.frames.length, 0);
  // `byteLength` is absent on vantages that do not tap the raw wire (dotli's
  // bridge), so an op contributes only the frames that carry a length.
  const bytes = views.reduce(
    (sum, v) => sum + v.frames.reduce((b, f) => b + (f.byteLength ?? 0), 0),
    0,
  );
  const live = views.filter(
    (v) =>
      v.frames.some((f) => f.role === "start") &&
      !v.frames.some((f) => f.role === "stop"),
  ).length;
  const done = views.filter((v) => v.durationMs > 0);
  const avg =
    done.length === 0
      ? 0
      : done.reduce((sum, v) => sum + v.durationMs, 0) / done.length;
  const orphaned = views.filter((v) => v.badges.includes("orphaned")).length;
  const storms = views.filter((v) => v.badges.includes("retry-storm")).length;

  // Top methods by frequency, rendered as the standalone's clickable pills.
  const counts = new Map<string, number>();
  for (const view of views) {
    const method = view.frames[0]?.method;
    if (method === undefined) continue;
    counts.set(method, (counts.get(method) ?? 0) + 1);
  }
  const pills = [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 4)
    .map(
      ([method, n]) =>
        `<span class="ins-method" data-method="${esc(method)}">` +
        `${esc(method)} <b>${String(n)}</b></span>`,
    )
    .join("");

  return (
    stat(String(views.length), "ops") +
    stat(String(frames), "frames") +
    stat(`${String(bytes)} B`, "bytes") +
    stat(String(live), "live sub", live > 0 ? "good" : "") +
    stat(formatMs(avg), "avg") +
    stat(String(orphaned), "orphaned", orphaned > 0 ? "warn" : "warn zero") +
    stat(String(storms), "retry storms", storms > 0 ? "warn" : "warn zero") +
    (pills === "" ? "" : `<span class="ins-methods">${pills}</span>`)
  );
}

/** Stable identity for an op across refreshes: channel + id + generation. */
function opKey(view: TraceView): string {
  return `${view.channelId ?? ""} ${view.requestId} ${String(view.generation ?? 0)}`;
}

/**
 * Create an in-app debugger. Decode is ON by default (dev-only tool); pass
 * `decodeValues: false` to keep a bundled mount payload-blind.
 */
export function createInAppDebugger(
  options: DebugSessionOptions = {},
): InAppDebugger {
  const session = createDebugSession(options);
  return {
    session,
    handleFrame(channelId, dir, frame) {
      session.handleEnvelope({ channelId, dir, frame });
    },
    mount(el, mountOptions = {}) {
      const style = document.createElement("style");
      // Scoped to the panel root: the embed styles its own container and never
      // reaches for `html`/`body`, which belong to the host page.
      style.textContent = `
.td-inapp { display: grid; grid-template-rows: auto auto minmax(0, 1fr) auto;
  height: 100%; min-height: 0; overflow: hidden; background: #0a0a0a; color: #e0e0e0;
  font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; }
.td-inapp * { box-sizing: border-box; }
${INSPECTOR_SHELL_CSS}
${TRACE_DETAIL_CSS}
${INSPECTOR_LAYOUT_CSS}`;

      const root = document.createElement("div");
      root.className = "td-inapp";
      root.innerHTML = `
<div class="ins-top">
  <span class="ins-title">TrUAPI <span class="accent">Wire Inspector</span></span>
  <input class="ins-filter" type="search" placeholder="filter methods…" autocomplete="off" spellcheck="false">
  <select class="ins-sort" title="Sort operations">
    <option value="arrival">arrival</option>
    <option value="slowest">slowest</option>
    <option value="frames">frames</option>
  </select>
  <span class="ins-channels"></span>
</div>
<div class="ins-summary empty"></div>
<div class="ins-body">
  <div class="ins-list" tabindex="0"><div class="td-op-empty">waiting for frames…</div></div>
  <div class="ins-split"></div>
  <div class="ins-detail" tabindex="0"><div class="td-detail-empty">Select an operation to inspect its frames.</div></div>
</div>
<div class="ins-status"></div>`;
      el.append(style, root);

      const pick = <T extends Element>(selector: string): T => {
        const node = root.querySelector<T>(selector);
        if (node === null) throw new Error(`in-app mount: missing ${selector}`);
        return node;
      };
      const filterEl = pick<HTMLInputElement>(".ins-filter");
      const sortEl = pick<HTMLSelectElement>(".ins-sort");
      const channelsEl = pick<HTMLElement>(".ins-channels");
      const summaryEl = pick<HTMLElement>(".ins-summary");
      const listEl = pick<HTMLElement>(".ins-list");
      const detailEl = pick<HTMLElement>(".ins-detail");
      const statusEl = pick<HTMLElement>(".ins-status");

      let selected: string | null = null;
      let channel: string | null = null;
      let disposed = false;

      const render = (): void => {
        if (disposed) return;
        const traces = session.traceEngine.traces();
        const storms = detectRetryStorms(traces);
        // One clock per render so every waiting op in this pass agrees, and the
        // 1s refresh makes a hung call visibly count up.
        const now = Date.now();
        const all = traces.map((trace) =>
          wireTraceToView(trace, session.methodNames, storms.get(trace) ?? []),
        );

        // Channel chips only earn their row once a second host has dialed in.
        const channelIds = [
          ...new Set(
            all
              .map((v) => v.channelId)
              .filter((c): c is string => c !== undefined),
          ),
        ];
        channelsEl.innerHTML =
          channelIds.length < 2
            ? ""
            : [null, ...channelIds]
                .map((c) => {
                  const active = c === channel ? " active" : "";
                  return (
                    `<button class="ins-chan${active}" data-channel="${esc(c ?? "")}">` +
                    `<span class="dot live"></span>${esc(c ?? "all")}</button>`
                  );
                })
                .join("");

        const scoped =
          channel === null ? all : all.filter((v) => v.channelId === channel);
        summaryEl.className = `ins-summary${scoped.length === 0 ? " empty" : ""}`;
        summaryEl.innerHTML = renderSummary(scoped);

        const needle = filterEl.value.trim().toLowerCase();
        const filtered =
          needle === ""
            ? scoped
            : scoped.filter((v) =>
                (v.frames[0]?.method ?? "").toLowerCase().includes(needle),
              );

        const sort = sortEl.value as SortMode;
        const ordered = [...filtered].sort((a, b) => {
          if (sort === "slowest") return b.durationMs - a.durationMs;
          if (sort === "frames") return b.frames.length - a.frames.length;
          return a.startedAt - b.startedAt;
        });

        listEl.innerHTML =
          ordered.length === 0
            ? `<div class="td-op-empty">${scoped.length === 0 ? "waiting for frames…" : "no operations match the filter"}</div>`
            : ordered
                .map((view) => {
                  const row = renderOperationRow(view, { now });
                  return opKey(view) === selected
                    ? row.replace('class="td-op ', 'class="td-op selected ')
                    : row;
                })
                .join("");

        const open = ordered.find((v) => opKey(v) === selected);
        detailEl.innerHTML =
          open === undefined
            ? `<div class="td-detail-empty">Select an operation to inspect its frames.</div>`
            : renderTraceDetail(open, {
                offerDecode: session.decodeValues,
                decoded: decodeTraceFrames(session, open),
              });

        const evicted = session.traceEngine.evictedTraces();
        statusEl.innerHTML =
          `<span>${String(all.length)} ops</span>` +
          `<span class="live">in-app · decode ${session.decodeValues ? "on" : "off"}</span>` +
          (evicted > 0
            ? `<span class="mismatch">${String(evicted)} evicted</span>`
            : "");
      };

      // Selecting a row is the only interaction that changes what the detail
      // pane shows, so re-render at once rather than waiting for the next tick.
      listEl.addEventListener("click", (event) => {
        const row = (event.target as HTMLElement).closest<HTMLElement>(".td-op");
        if (row === null) return;
        const key = [
          row.dataset["channelId"] ?? "",
          row.dataset["requestId"] ?? "",
          row.dataset["generation"] ?? "0",
        ].join(" ");
        selected = selected === key ? null : key;
        render();
      });
      channelsEl.addEventListener("click", (event) => {
        const chip = (event.target as HTMLElement).closest<HTMLElement>(
          ".ins-chan",
        );
        if (chip === null) return;
        const value = chip.dataset["channel"] ?? "";
        channel = value === "" ? null : value;
        render();
      });
      summaryEl.addEventListener("click", (event) => {
        const pill = (event.target as HTMLElement).closest<HTMLElement>(
          ".ins-method",
        );
        if (pill === null) return;
        filterEl.value = pill.dataset["method"] ?? "";
        render();
      });
      filterEl.addEventListener("input", render);
      sortEl.addEventListener("change", render);

      render();
      const timer = setInterval(render, mountOptions.refreshMs ?? 1000);
      return () => {
        disposed = true;
        clearInterval(timer);
        style.remove();
        root.remove();
      };
    },
  };
}
