// Worker half of the two host-initiated Renderer entry points. Both reach the
// core directly rather than through the frame path, because neither is a
// product request: the host starts the render subscription, and the host
// publishes the action a rendered body produced.

import type {
  WorkerRendererSubscription,
  WorkerProductRuntime,
} from "./wasm-module.js";
import type { WorkerToMain } from "./worker-protocol.js";
import { errorMessage } from "./error.js";

type PostToMain = (msg: WorkerToMain) => void;

/**
 * Live render subscriptions, keyed by the main thread's render id. The core id
 * rides along so disposing one core cancels only its own renders.
 */
export type RenderSubscriptions = Map<
  number,
  { coreId: number; subscription: WorkerRendererSubscription }
>;

/** Hand one host-authored renderer action to the core and answer the caller. */
export function handlePublishRendererAction(
  core: WorkerProductRuntime | undefined,
  postToMain: PostToMain,
  coreId: number,
  requestId: number,
  item: Uint8Array,
): void {
  if (!core) {
    postToMain({
      kind: "publishRendererActionResponse",
      requestId,
      ok: false,
      error: `publishRendererAction received for unknown core ${coreId}`,
    });
    return;
  }
  try {
    core.publishRendererAction(item);
    postToMain({ kind: "publishRendererActionResponse", requestId, ok: true });
  } catch (err) {
    postToMain({
      kind: "publishRendererActionResponse",
      requestId,
      ok: false,
      error: errorMessage(err),
    });
  }
}

/**
 * Open one render stream on the core and forward its items to the main thread.
 * Exactly one terminal is posted per render.
 */
export function handleRenderStart(
  core: WorkerProductRuntime | undefined,
  postToMain: PostToMain,
  renders: RenderSubscriptions,
  coreId: number,
  renderId: number,
  request: Uint8Array,
): void {
  if (!core) {
    postToMain({
      kind: "renderError",
      renderId,
      error: `render received for unknown core ${coreId}`,
    });
    return;
  }
  try {
    const subscription = core.render(
      request,
      (node) => postToMain({ kind: "renderItem", renderId, node }),
      () => {
        stopRender(renders, renderId);
        postToMain({ kind: "renderComplete", renderId });
      },
      (reason) => {
        stopRender(renders, renderId);
        postToMain({ kind: "renderError", renderId, error: reason });
      },
    );
    renders.set(renderId, { coreId, subscription });
  } catch (err) {
    postToMain({
      kind: "renderError",
      renderId,
      error: errorMessage(err),
    });
  }
}

/** Cancel and release one render subscription. Idempotent. */
export function stopRender(
  renders: RenderSubscriptions,
  renderId: number,
): void {
  const entry = renders.get(renderId);
  if (!entry) return;
  renders.delete(renderId);
  entry.subscription.cancel();
  entry.subscription.free();
}

/** Cancel every render belonging to one core, before that core is freed. */
export function stopRendersForCore(
  renders: RenderSubscriptions,
  coreId: number,
): void {
  for (const [renderId, entry] of [...renders]) {
    if (entry.coreId === coreId) stopRender(renders, renderId);
  }
}
