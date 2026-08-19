// Copyright 2026 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: MIT
/**
 * The presentation model the drill-down renderer works in.
 *
 * A {@link WireTrace} is the *engine* contract: raw {@link ObservedFrame}s
 * grouped by `requestId`. The drill-down UI is mounted in two places with
 * structurally different taps behind them:
 *
 *  - the standalone app taps the raw wire (numeric `frameId`, `byteLength`,
 *    optional `bytes`), and resolves method names through the wire table;
 *  - dotli's panel taps the post-decode host-container bridge, so it has a
 *    method `tag` and a decoded payload but no wire discriminant or byte count.
 *
 * A single renderer over raw {@link WireTrace} would force one of those two to
 * fake the other's fields. {@link TraceView} is the honest shared surface: a
 * normalized per-op view both vantages can populate, with vantage-specific
 * fields left optional. {@link wireTraceToView} is the wire-vantage adapter;
 * dotli ships its own adapter over the same shape.
 *
 * The `WireTrace`/envelope/level-2 contract is unchanged by this module: it
 * only reads a `WireTrace` and produces a view.
 *
 * @module
 */

import type { FrameDirection, FrameRole } from "./observed-frame.js";
import type {
  TraceDropCounts,
  WireMethodInfo,
  WireTrace,
} from "./wire-debugger.js";

/**
 * An op-level badge, surfaced against the whole trace in the drill-down header.
 *
 *  - `orphaned`: the trace has an opening frame with no matching close (a
 *    request with no response, a subscribe with no receive) or a close with no
 *    opening. Signals a dropped or still-in-flight op.
 *  - `malformed`: at least one frame failed to decode on the wire.
 *  - `retry-storm`: the op is one of a burst of like ops in a short window.
 *    This is a *cross-op* signal the single-trace renderer cannot see on its
 *    own, so it is supplied by the caller (the list/engine layer) rather than
 *    derived here. Left as a follow-up for the engine to compute.
 *  - `truncated`: older frames of this op were dropped to stay under the engine's
 *    frame/byte cap, so the sequence shown is not the whole op. How many, and
 *    which cap took them, is in {@link TraceView.dropped}. Because the dropped
 *    frames may be the ones that answered the opener, a truncated op does not
 *    derive `orphaned`.
 */
export type TraceBadge = "orphaned" | "malformed" | "retry-storm" | "truncated";

/** A per-frame badge, surfaced against a single row in the frame sequence. */
export type TraceFrameBadge = "malformed" | "orphaned";

/** One frame of an op, normalized for rendering. */
export interface TraceFrameView {
  /**
   * Stable index within the view. Used as the keyboard-navigation cursor and,
   * for level-2, the target a decode action addresses.
   */
  seq: number;
  /** Product-vantage direction: `out` left the product, `in` arrived at it. */
  direction: FrameDirection;
  /** Best-effort lifecycle role (request/response/receive/...). */
  role: FrameRole;
  /** Resolved dotted method, e.g. `account.getAccount`, when known. */
  method?: string;
  /** Wire discriminant, present on the raw-wire vantage. */
  frameId?: number;
  /** Encoded payload length in bytes, present when the vantage measures it. */
  byteLength?: number;
  /** Epoch ms the frame was observed. */
  timestamp: number;
  /**
   * Offset in ms from the trace's first frame. Debugger-observed: measured from
   * the debugger's envelope-arrival clock, so it includes WS transport and
   * queueing delay. Reliable for ordering and presence, not a host-side latency.
   */
  latencyFromStartMs: number;
  /**
   * Round-trip in ms from this frame back to the opening frame it answers,
   * present only on a closing frame that has a matched opener. Debugger-observed
   * (see {@link latencyFromStartMs}): it includes transport/queueing, so it is
   * not the host's "this call took N ms".
   */
  roundTripMs?: number;
  /** Badges for this frame alone. */
  badges: TraceFrameBadge[];
  /**
   * Whether a level-2 payload decode can even be attempted for this frame:
   * raw bytes were captured for it. Payload-blind by default regardless; this
   * only gates whether the affordance is *offered*.
   */
  decodable: boolean;
}

/** A whole op, normalized for the drill-down view. */
export interface TraceView {
  /** Correlation id shared by every frame in the op. */
  requestId: string;
  /**
   * Channel/host the op belongs to, when the vantage supplies it. `requestId`
   * is minted per-transport and is not unique across hosts dialing one debugger,
   * so the op list keys and filters on `(channelId, requestId)`.
   */
  channelId?: string;
  /**
   * Which reuse of `(channelId, requestId)` this op is, from `0`. A product may
   * recycle a requestId for a later call; this lets the op list and drill-down
   * address the right op instead of merging or masking one.
   */
  generation?: number;
  /** Epoch ms of the first frame. */
  startedAt: number;
  /** Epoch ms of the most recent frame. */
  lastAt: number;
  /** Total wall-clock span of the op in ms (`lastAt - startedAt`). */
  durationMs: number;
  /** Frames in arrival order. */
  frames: TraceFrameView[];
  /** Op-level badges. */
  badges: TraceBadge[];
  /**
   * What the vantage's retention caps dropped from this op, per axis, when the
   * vantage caps at all (the wire engine does; dotli's bridge does not, and
   * leaves this unset). The `truncated` badge says only *that* frames are
   * missing; these counts say how many and which cap took them.
   */
  dropped?: TraceDropCounts;
}

/** Roles that open an op (expect a matching close later in the trace). */
const OPENING_ROLES: ReadonlySet<FrameRole> = new Set<FrameRole>([
  "request",
  "start",
]);

/** Roles that close or continue an op (expect a matching opener earlier). */
const CLOSING_ROLES: ReadonlySet<FrameRole> = new Set<FrameRole>([
  "response",
  "receive",
  "interrupt",
  "stop",
]);

/**
 * Roles that mark an op as a subscription rather than a request/response. A
 * `receive`/`stop`/`interrupt` is enough on its own: the debugger can attach
 * mid-session and never see the `start`.
 */
const SUBSCRIPTION_ROLES: ReadonlySet<FrameRole> = new Set<FrameRole>([
  "start",
  "receive",
  "stop",
  "interrupt",
]);

/**
 * Roles that end a subscription for good, so no further `receive` is expected:
 * the product's own `stop`, or the host's `interrupt`. Deliberately *not*
 * {@link CLOSING_ROLES}, which also contains `receive` - a receive continues a
 * subscription rather than ending it.
 */
const TERMINAL_ROLES: ReadonlySet<FrameRole> = new Set<FrameRole>([
  "stop",
  "interrupt",
]);

/**
 * One frame described by a mount's adapter, before the view-level fields (`seq`,
 * latency, pairing, badges) are computed. The two vantages differ in what they
 * can fill: the wire vantage has `frameId`/`byteLength`/`bytes`; dotli's bridge
 * vantage has a `method` off the tag but no wire id or byte count. Everything
 * optional here is genuinely absent on one side, not merely unset.
 */
export interface TraceFrameInput {
  direction: FrameDirection;
  role: FrameRole;
  method?: string;
  frameId?: number;
  byteLength?: number;
  timestamp: number;
  /** Whether a level-2 decode can be attempted (raw bytes were retained). */
  decodable: boolean;
}

/** The raw shape a mount adapter hands to {@link buildTraceView}. */
export interface TraceViewInput {
  requestId: string;
  /** Channel/host the op belongs to, when the vantage supplies it. */
  channelId?: string;
  /** Which reuse of `(channelId, requestId)` this op is; see {@link TraceView.generation}. */
  generation?: number;
  startedAt: number;
  lastAt: number;
  frames: readonly TraceFrameInput[];
  /**
   * Op-level signals the caller computes across traces (e.g. `retry-storm`).
   * Within-trace badges (`orphaned`, `malformed`, `truncated`) are derived here.
   */
  extraBadges?: readonly TraceBadge[];
  /**
   * What the vantage's retention caps dropped, when it caps. Drives the
   * `truncated` badge, and suppresses the `orphaned` verdict on an opener whose
   * answering frames may be among the evicted.
   */
  dropped?: TraceDropCounts;
}

/**
 * The vantage-agnostic core: assign each frame its `seq` and latency, pair
 * openers with closers to fill `roundTripMs` and flag orphans, then roll frame
 * badges up to the op. Both mount adapters ({@link wireTraceToView} and dotli's)
 * funnel through this so the frame sequence, latencies, and badges are computed
 * identically regardless of vantage.
 */
export function buildTraceView(input: TraceViewInput): TraceView {
  const frames: TraceFrameView[] = input.frames.map((frame, index) => ({
    seq: index,
    direction: frame.direction,
    role: frame.role,
    method: frame.method,
    frameId: frame.frameId,
    byteLength: frame.byteLength,
    timestamp: frame.timestamp,
    latencyFromStartMs: frame.timestamp - input.startedAt,
    badges: frame.role === "malformed" ? ["malformed"] : [],
    decodable: frame.decodable,
  }));

  // Frames actually missing from the sequence (a shed payload leaves its frame in
  // place, so it does not count): the answering frames of an opener may be among
  // them, which makes an "opener never answered" verdict unsound.
  const framesEvicted =
    (input.dropped?.framesByCount ?? 0) + (input.dropped?.framesByBytes ?? 0) >
    0;
  const anythingDropped =
    framesEvicted || (input.dropped?.payloadsShed ?? 0) > 0;

  annotatePairing(frames, framesEvicted);

  const extraBadges = anythingDropped
    ? [...(input.extraBadges ?? []), "truncated" as const]
    : (input.extraBadges ?? []);

  return {
    requestId: input.requestId,
    channelId: input.channelId,
    generation: input.generation,
    startedAt: input.startedAt,
    lastAt: input.lastAt,
    durationMs: input.lastAt - input.startedAt,
    frames,
    badges: deriveOpBadges(frames, extraBadges),
    dropped: input.dropped,
  };
}

/**
 * THE definition of an op's method, for display, filtering, sorting and stats:
 * the opening (request/start) frame's method, else the first frame that resolves
 * one, else `undefined` when no frame's id was on the table. Every consumer -
 * both mounts, the op row, the summary stats - must call this rather than
 * re-deriving it, so an op is never named one thing in the list and another in
 * the stats. Callers that need a placeholder supply their own (`?? "(unknown)"`).
 */
export function operationMethod(view: TraceView): string | undefined {
  const opener = view.frames.find((f) => OPENING_ROLES.has(f.role));
  if (opener?.method !== undefined) return opener.method;
  return view.frames.find((f) => f.method !== undefined)?.method;
}

/** Whether the op is a subscription (has a start/receive/stop/interrupt frame). */
export function isSubscription(view: TraceView): boolean {
  return view.frames.some((f) => SUBSCRIPTION_ROLES.has(f.role));
}

/**
 * THE definition of a live subscription: a subscription op that has not been
 * terminated by either side. Every consumer - the op row's `live` marker, the
 * standalone summary's `liveSubscriptions` tile, the in-app panel's "live sub"
 * stat - must call this rather than re-deriving it, or the same session reports
 * different numbers in different places.
 *
 * Termination is {@link TERMINAL_ROLES}: a product `stop` *or* a host
 * `interrupt`. Testing only for `stop` leaves every host-terminated subscription
 * reading "live" forever, which inflates the live count monotonically.
 */
export function isLiveSubscription(view: TraceView): boolean {
  return (
    isSubscription(view) && !view.frames.some((f) => TERMINAL_ROLES.has(f.role))
  );
}

/**
 * Adapt a raw-wire {@link WireTrace} into a {@link TraceView}. Method names are
 * resolved through the wire table (`frameId → method`); byte lengths and the
 * `decodable` flag come straight off the observed frames.
 */
export function wireTraceToView(
  trace: WireTrace,
  methodNames?: ReadonlyMap<number, WireMethodInfo>,
  extraBadges: readonly TraceBadge[] = [],
): TraceView {
  return buildTraceView({
    requestId: trace.requestId,
    channelId: trace.channelId,
    generation: trace.generation,
    startedAt: trace.startedAt,
    lastAt: trace.lastAt,
    // Engine-level frame/byte-cap eviction: `dropped` drives the `truncated`
    // badge and the orphan suppression in buildTraceView.
    extraBadges,
    dropped: trace.dropped,
    frames: trace.frames.map((frame): TraceFrameInput => {
      // A frame may still arrive `role: "unknown"` (a vantage with no wire
      // frameId, or an off-table id); the frameId's wire-table `kind` is the
      // lifecycle role, so use it as the fallback. A `"malformed"` sentinel is kept.
      const info = methodNames?.get(frame.frameId);
      const role =
        frame.role === "unknown" && info !== undefined ? info.kind : frame.role;
      return {
        direction: frame.direction,
        role,
        method: info?.method,
        frameId: frame.frameId,
        byteLength: frame.byteLength,
        timestamp: frame.timestamp,
        decodable: frame.bytes !== undefined && frame.bytes.length > 0,
      };
    }),
  });
}

/**
 * Second pass over the frame sequence: pair openers with closers to fill in
 * `roundTripMs` and flag `orphaned` frames.
 *
 * All frames of a trace share one `requestId`, so pairing is positional: each
 * closing frame answers the most recent opener. An opener that never got any
 * close is orphaned (a request with no response, a subscribe that never
 * delivered); a closer with no opener before it is orphaned. An opener that got
 * at least one close is not orphaned even if it stays open - a live
 * subscription (start + receives, no stop yet) is healthy, not dropped.
 *
 * `framesEvicted` says frames are missing from this sequence because a retention
 * cap dropped them. Caps only ever evict from index 1, so the opener is still
 * here but the frames that answered it may not be: "no close was observed" no
 * longer implies "no close happened", and the opener is left unflagged rather
 * than blamed for the engine's own eviction. A closer with no opener is still
 * orphaned - an opener is never the frame that gets evicted.
 */
function annotatePairing(
  views: TraceFrameView[],
  framesEvicted: boolean,
): void {
  const openStack: number[] = [];
  const matched = new Set<number>();
  for (let i = 0; i < views.length; i++) {
    const view = views[i];
    if (OPENING_ROLES.has(view.role)) {
      openStack.push(i);
      continue;
    }
    if (CLOSING_ROLES.has(view.role)) {
      const openerIndex =
        openStack.length > 0 ? openStack[openStack.length - 1] : undefined;
      if (openerIndex === undefined) {
        markOrphan(view);
        continue;
      }
      view.roundTripMs = view.timestamp - views[openerIndex].timestamp;
      matched.add(openerIndex);
      // A `receive` keeps the subscription open for later receives; any other
      // close terminates the op and pops its opener.
      if (view.role !== "receive") {
        openStack.pop();
      }
    }
  }
  // Openers still open AND never answered are orphaned; a matched-but-open
  // opener (live subscription) is not. Under eviction the answering frames may
  // simply have been dropped, so no opener verdict is sound.
  if (framesEvicted) return;
  for (const openerIndex of openStack) {
    if (!matched.has(openerIndex)) {
      markOrphan(views[openerIndex]);
    }
  }
}

function markOrphan(view: TraceFrameView): void {
  if (!view.badges.includes("orphaned")) {
    view.badges.push("orphaned");
  }
}

/** Collapse per-frame badges plus caller-supplied signals into op-level badges. */
function deriveOpBadges(
  frames: readonly TraceFrameView[],
  extraBadges: readonly TraceBadge[],
): TraceBadge[] {
  const badges = new Set<TraceBadge>(extraBadges);
  for (const frame of frames) {
    if (frame.badges.includes("malformed")) {
      badges.add("malformed");
    }
    if (frame.badges.includes("orphaned")) {
      badges.add("orphaned");
    }
  }
  return [...badges];
}
