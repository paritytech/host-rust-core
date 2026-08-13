// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: MIT
/**
 * The inspector chrome: every rule the Network-tab shell needs that is not a
 * per-frame drill-down rule (those live in `trace-styles.ts`).
 *
 * Shared so the two mounts cannot drift apart visually. The standalone app puts
 * the shell in a full page; the in-app embed puts the same shell in a panel
 * inside the host. Neither owns these rules, so a change lands in both.
 *
 * Deliberately free of page-level rules (`html`, `body`, viewport units): a mount
 * scopes its own container, and an embed must never restyle its host's page.
 *
 * @module
 */

/**
 * The shell: top bar, channel chips, the list/detail split, and operation rows.
 * Pair with {@link TRACE_DETAIL_CSS} and {@link INSPECTOR_LAYOUT_CSS}.
 */
export const INSPECTOR_SHELL_CSS = `
  .ins-top { display: flex; align-items: center; gap: 12px; padding: 6px 12px;
    border-bottom: 1px solid rgba(255,255,255,.08); }
  .ins-title { font-weight: 600; letter-spacing: .02em; white-space: nowrap; }
  .ins-title .accent { color: #4ade80; }
  .ins-channels { display: flex; gap: 6px; flex: 1; flex-wrap: wrap; }
  .ins-chan { display: inline-flex; align-items: center; gap: 5px; padding: 1px 9px;
    border: 1px solid rgba(255,255,255,.12); border-radius: 10px; background: transparent;
    color: #94a3b8; cursor: pointer; font: inherit; }
  .ins-chan.active { color: #0a0a0a; background: #4ade80; border-color: #4ade80; }
  .ins-chan .dot { width: 6px; height: 6px; border-radius: 50%; background: #4b5563; }
  .ins-chan .dot.live { background: #4ade80; box-shadow: 0 0 4px #4ade80; }
  .ins-chan.active .dot.live { background: #0a0a0a; box-shadow: none; }
  .ins-body { display: grid; grid-template-columns: var(--list-w, 340px) 6px 1fr;
    min-height: 0; }
  .ins-list { overflow: auto; outline: none; }
  .ins-split { cursor: col-resize; background: rgba(255,255,255,.05); }
  .ins-split:hover { background: rgba(74,222,128,.4); }
  .ins-detail { overflow: auto; padding: 8px 12px; outline: none; }
  .td-op { display: flex; align-items: center; gap: 8px; padding: 4px 10px;
    cursor: pointer; border-bottom: 1px solid rgba(255,255,255,.03); }
  .td-op:hover { background: rgba(255,255,255,.04); }
  .td-op.selected { background: rgba(74,222,128,.13); }
  .ins-list:focus-visible .td-op.selected { box-shadow: inset 2px 0 0 #4ade80; }
  .td-op-kind { width: 12px; text-align: center; }
  .td-op-req .td-op-kind { color: #fbbf24; }
  .td-op-sub .td-op-kind { color: #c084fc; }
  /* Truncate the *start*, not the end: sibling methods share a service prefix
     (account.getAccount vs account.getAccountAlias), so clipping the tail
     renders two different methods identically. Keeping the tail makes them
     distinguishable in a narrow list. */
  .td-op-method { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    direction: rtl; text-align: left; }
  /* An op that went out and is still unanswered: counts up, and reads as a
     problem rather than a completed 0ms call. */
  .td-op-waiting .td-op-meta { color: #fbbf24; }
  .td-op-method.anon { color: #525252; font-style: italic; }
  .td-op-meta { color: #6b7280; font-size: 10.5px; white-space: nowrap; }
  .td-op-live .td-op-meta { color: #4ade80; }
  .td-op-badges { display: inline-flex; gap: 4px; }
  .td-op-empty, .td-detail-empty { color: #6b7280; padding: 14px; }
  .td-frame.cursor { background: rgba(255,255,255,.06); box-shadow: inset 2px 0 0 #94a3b8; }
`;

/**
 * App-level layout applied on top of the shared drill-down rules: the two-column
 * frame grid, the filter/sort controls, and the aggregate summary strip.
 * Applied after {@link TRACE_DETAIL_CSS} because it overrides some of it.
 */
export const INSPECTOR_LAYOUT_CSS = `
  /* App-level layout for the drill-down (trace-styles.ts stays untouched).
     Each frame is a two-column grid: meta on the left, a fixed-width payload
     column on the right, so every frame's decoded / blurred box opens in the
     same aligned partitioned space instead of trailing variable-width meta. */
  .ins-detail { padding: 6px 10px 10px; }
  .td-frame { display: grid; align-items: start; column-gap: 10px;
    grid-template-columns: minmax(0, 1fr); padding: 4px 8px; }
  .td-frame:has(.td-frame-payload) {
    grid-template-columns: minmax(0, 1fr) var(--payload-w, clamp(240px, 44%, 520px)); }
  .td-frame-meta { display: flex; align-items: center; gap: 8px; min-width: 0; }
  .td-frame-meta .td-frame-method { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .td-frames .td-frame:nth-child(even) { background: rgba(255,255,255,.02); }
  .td-frame:hover { background: rgba(255,255,255,.05); }
  /* The payload column: same width for every frame; content scrolls inside. */
  .td-frame-payload { min-width: 0; }
  .td-frame-decoded > * { margin: 0; }
  .td-frame-decoded .td-detail-pre { max-height: 240px; overflow: auto; margin: 0;
    white-space: pre; }
  /* Top-bar filter / sort controls. */
  .ins-filter { width: 148px; padding: 2px 8px; border: 1px solid rgba(255,255,255,.14);
    border-radius: 5px; background: rgba(255,255,255,.03); color: #e0e0e0; font: inherit; }
  .ins-filter:focus { outline: none; border-color: rgba(74,222,128,.5); }
  .ins-sort { padding: 2px 6px; border: 1px solid rgba(255,255,255,.14); border-radius: 5px;
    background: #0a0a0a; color: #cbd5e1; font: inherit; cursor: pointer; }
  .td-op.filtered-out { display: none; }
  /* Clickable top-method pills. */
  .ins-method { cursor: pointer; }
  .ins-method:hover { border-color: rgba(74,222,128,.5); color: #d1fae5; }
  /* Aggregate summary strip: the "at a glance" row of metric tiles. */
  .ins-summary { display: flex; gap: 6px; align-items: flex-start; flex-wrap: nowrap;
    padding: 6px 12px; border-bottom: 1px solid rgba(255,255,255,.08);
    background: rgba(255,255,255,.02); overflow-x: auto; }
  .ins-stat { display: flex; flex-direction: column; gap: 1px; padding: 2px 10px 2px 0;
    border-right: 1px solid rgba(255,255,255,.06); }
  .ins-stat:last-child { border-right: 0; }
  .ins-stat .n { font-size: 14px; font-weight: 600; color: #f1f5f9;
    font-variant-numeric: tabular-nums; line-height: 1.15; }
  .ins-stat .k { font-size: 9.5px; text-transform: uppercase; letter-spacing: .06em; color: #64748b; }
  .ins-stat.warn .n { color: #f87171; }
  .ins-stat.warn.zero .n { color: #475569; }
  .ins-stat.good .n { color: #4ade80; }
  .ins-stat .sub { color: #64748b; font-weight: 400; font-size: 10px; }
  /* Pills stay on one row, pushed right; when the viewport is too narrow the
     whole summary scrolls (overflow-x above) rather than the pills wrapping to a
     second line. */
  .ins-methods { display: flex; align-items: center; gap: 6px; margin-left: auto;
    flex: 0 0 auto; flex-wrap: nowrap; }
  .ins-method { white-space: nowrap; }
  .ins-method { display: inline-flex; align-items: center; gap: 5px; padding: 1px 8px;
    border: 1px solid rgba(255,255,255,.08); border-radius: 10px; color: #94a3b8;
    font-size: 10.5px; white-space: nowrap; }
  .ins-method b { color: #cbd5e1; font-variant-numeric: tabular-nums; }
  .ins-summary.empty { color: #64748b; }
  .ins-status { display: flex; gap: 16px; padding: 4px 12px; color: #6b7280;
    border-top: 1px solid rgba(255,255,255,.08); }
  .ins-status .live { color: #4ade80; }
  .ins-status .mismatch { color: #f87171; }
`;
