// Worker half of the host-initiated Chat entry point. It reaches the core
// directly rather than through the frame path, because it is not a product
// request: the host publishes the action a chat surface produced.

import type { WorkerProductRuntime } from "./wasm-module.js";
import type { WorkerToMain } from "./worker-protocol.js";
import { errorMessage } from "./error.js";

type PostToMain = (msg: WorkerToMain) => void;

/** Hand one host-authored chat action to the core and answer the caller. */
export function handlePublishChatAction(
  core: WorkerProductRuntime | undefined,
  postToMain: PostToMain,
  coreId: number,
  requestId: number,
  action: Uint8Array,
): void {
  if (!core) {
    postToMain({
      kind: "publishChatActionResponse",
      requestId,
      ok: false,
      error: `publishChatAction received for unknown core ${coreId}`,
    });
    return;
  }
  try {
    core.publishChatAction(action);
    postToMain({ kind: "publishChatActionResponse", requestId, ok: true });
  } catch (err) {
    postToMain({
      kind: "publishChatActionResponse",
      requestId,
      ok: false,
      error: errorMessage(err),
    });
  }
}
