// Worker half of the host-initiated action entry points. Both reach the core
// directly rather than through the frame path, because neither is a product
// request: the host publishes the action a surface it drew produced.

import type { WorkerProductRuntime } from "./wasm-module.js";
import type { WorkerToMain } from "./worker-protocol.js";
import { errorMessage } from "./error.js";

type PostToMain = (msg: WorkerToMain) => void;

/** One host-initiated action entry point: what it is called and what it calls. */
export interface ActionEntryPoint {
  /** Request kind the host posts; the response kind is this plus `Response`. */
  name: "publishChatAction" | "publishRendererAction";
  /** Core method the encoded action item is handed to. */
  publish: (core: WorkerProductRuntime, item: Uint8Array) => void;
}

/** The Chat action stream, carrying a `HostChatActionSubscribeItem`. */
export const CHAT_ACTION_ENTRY_POINT: ActionEntryPoint = {
  name: "publishChatAction",
  publish: (core, item) => core.publishChatAction(item),
};

/** The Renderer action stream, carrying a `HostRendererActionSubscribeItem`. */
export const RENDERER_ACTION_ENTRY_POINT: ActionEntryPoint = {
  name: "publishRendererAction",
  publish: (core, item) => core.publishRendererAction(item),
};

/** Hand one host-authored action to the core and answer the caller. */
export function handlePublishAction(
  entryPoint: ActionEntryPoint,
  core: WorkerProductRuntime | undefined,
  postToMain: PostToMain,
  coreId: number,
  requestId: number,
  item: Uint8Array,
): void {
  const kind = `${entryPoint.name}Response` as const;
  if (!core) {
    postToMain({
      kind,
      requestId,
      ok: false,
      error: `${entryPoint.name} received for unknown core ${coreId}`,
    });
    return;
  }
  try {
    entryPoint.publish(core, item);
    postToMain({ kind, requestId, ok: true });
  } catch (err) {
    postToMain({ kind, requestId, ok: false, error: errorMessage(err) });
  }
}
