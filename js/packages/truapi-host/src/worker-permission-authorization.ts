import type { PermissionAuthorizationStatus } from "./runtime.js";
import type { WorkerToMain } from "./worker-protocol.js";
import { errorMessage } from "./error.js";

export interface PermissionAuthorizationRuntime {
  permissionAuthorizationStatus(
    productId: string,
    artifactSha256: Uint8Array,
    request: Uint8Array,
  ): Promise<PermissionAuthorizationStatus>;
  permissionAuthorizationStatuses(
    productId: string,
    artifactSha256: Uint8Array,
    requests: Uint8Array[],
  ): Promise<PermissionAuthorizationStatus[]>;
  setPermissionAuthorizationStatus(
    productId: string,
    artifactSha256: Uint8Array,
    request: Uint8Array,
    status: PermissionAuthorizationStatus,
  ): Promise<void>;
}

type PostToMain = (msg: WorkerToMain) => void;

export async function handleGetPermissionAuthorizationStatus(
  runtime: PermissionAuthorizationRuntime | null,
  postToMain: PostToMain,
  productId: string,
  artifactSha256: Uint8Array,
  requestId: number,
  request: Uint8Array,
): Promise<void> {
  if (!runtime) {
    postToMain({
      kind: "permissionAuthorizationStatusResponse",
      requestId,
      ok: false,
      error: "permissionAuthorizationStatus received before runtime is ready",
    });
    return;
  }
  try {
    const status = await runtime.permissionAuthorizationStatus(
      productId,
      artifactSha256,
      request,
    );
    postToMain({
      kind: "permissionAuthorizationStatusResponse",
      requestId,
      ok: true,
      status,
    });
  } catch (err) {
    postToMain({
      kind: "permissionAuthorizationStatusResponse",
      requestId,
      ok: false,
      error: errorMessage(err),
    });
  }
}

export async function handleGetPermissionAuthorizationStatuses(
  runtime: PermissionAuthorizationRuntime | null,
  postToMain: PostToMain,
  productId: string,
  artifactSha256: Uint8Array,
  requestId: number,
  requests: Uint8Array[],
): Promise<void> {
  if (!runtime) {
    postToMain({
      kind: "permissionAuthorizationStatusesResponse",
      requestId,
      ok: false,
      error: "permissionAuthorizationStatuses received before runtime is ready",
    });
    return;
  }
  try {
    const statuses = await runtime.permissionAuthorizationStatuses(
      productId,
      artifactSha256,
      requests,
    );
    postToMain({
      kind: "permissionAuthorizationStatusesResponse",
      requestId,
      ok: true,
      statuses,
    });
  } catch (err) {
    postToMain({
      kind: "permissionAuthorizationStatusesResponse",
      requestId,
      ok: false,
      error: errorMessage(err),
    });
  }
}

export async function handleSetPermissionAuthorizationStatus(
  runtime: PermissionAuthorizationRuntime | null,
  postToMain: PostToMain,
  productId: string,
  artifactSha256: Uint8Array,
  requestId: number,
  request: Uint8Array,
  status: PermissionAuthorizationStatus,
): Promise<void> {
  if (!runtime) {
    postToMain({
      kind: "setPermissionAuthorizationStatusResponse",
      requestId,
      ok: false,
      error:
        "setPermissionAuthorizationStatus received before runtime is ready",
    });
    return;
  }
  try {
    await runtime.setPermissionAuthorizationStatus(
      productId,
      artifactSha256,
      request,
      status,
    );
    postToMain({
      kind: "setPermissionAuthorizationStatusResponse",
      requestId,
      ok: true,
    });
  } catch (err) {
    postToMain({
      kind: "setPermissionAuthorizationStatusResponse",
      requestId,
      ok: false,
      error: errorMessage(err),
    });
  }
}
