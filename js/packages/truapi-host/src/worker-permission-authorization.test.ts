import { describe, expect, it } from "bun:test";

import type { PermissionAuthorizationStatus } from "./runtime.js";
import type { WorkerToMain } from "./worker-protocol.js";
import {
  handleGetPermissionAuthorizationStatus,
  handleGetPermissionAuthorizationStatuses,
  handleSetPermissionAuthorizationStatus,
  type PermissionAuthorizationRuntime,
} from "./worker-permission-authorization.js";

const PRODUCT_ID = "playground.dot";
const ARTIFACT_SHA256 = new Uint8Array(32).fill(0x42);

function recordMessages() {
  const messages: WorkerToMain[] = [];
  return {
    messages,
    postToMain(msg: WorkerToMain): void {
      messages.push(msg);
    },
  };
}

function makeRuntime(
  overrides: Partial<PermissionAuthorizationRuntime> = {},
): PermissionAuthorizationRuntime {
  return {
    permissionAuthorizationStatus: async () => "NotDetermined",
    permissionAuthorizationStatuses: async (
      productId,
      artifactSha256,
      requests,
    ) => {
      void productId;
      void artifactSha256;
      return requests.map(() => "NotDetermined");
    },
    setPermissionAuthorizationStatus: async () => {},
    ...overrides,
  };
}

describe("worker permission authorization handlers", () => {
  it("responds with a single permission authorization status", async () => {
    const { messages, postToMain } = recordMessages();
    const request = new Uint8Array([1, 2, 3]);
    const calls: {
      productId: string;
      artifactSha256: Uint8Array;
      request: Uint8Array;
    }[] = [];
    const runtime = makeRuntime({
      permissionAuthorizationStatus: async (
        productId,
        artifactSha256,
        receivedRequest,
      ) => {
        calls.push({ productId, artifactSha256, request: receivedRequest });
        return "Authorized";
      },
    });

    await handleGetPermissionAuthorizationStatus(
      runtime,
      postToMain,
      PRODUCT_ID,
      ARTIFACT_SHA256,
      7,
      request,
    );

    expect(calls).toEqual([
      {
        productId: PRODUCT_ID,
        artifactSha256: ARTIFACT_SHA256,
        request,
      },
    ]);
    expect(messages).toEqual([
      {
        kind: "permissionAuthorizationStatusResponse",
        requestId: 7,
        ok: true,
        status: "Authorized",
      },
    ]);
  });

  it("responds with batched permission authorization statuses", async () => {
    const { messages, postToMain } = recordMessages();
    const requests = [new Uint8Array([1]), new Uint8Array([2])];
    const statuses: PermissionAuthorizationStatus[] = ["Denied", "Authorized"];
    const calls: {
      productId: string;
      artifactSha256: Uint8Array;
      requests: Uint8Array[];
    }[] = [];
    const runtime = makeRuntime({
      permissionAuthorizationStatuses: async (
        productId,
        artifactSha256,
        receivedRequests,
      ) => {
        calls.push({
          productId,
          artifactSha256,
          requests: receivedRequests,
        });
        return statuses;
      },
    });

    await handleGetPermissionAuthorizationStatuses(
      runtime,
      postToMain,
      PRODUCT_ID,
      ARTIFACT_SHA256,
      8,
      requests,
    );

    expect(calls).toEqual([
      {
        productId: PRODUCT_ID,
        artifactSha256: ARTIFACT_SHA256,
        requests,
      },
    ]);
    expect(messages).toEqual([
      {
        kind: "permissionAuthorizationStatusesResponse",
        requestId: 8,
        ok: true,
        statuses,
      },
    ]);
  });

  it("responds after setting a permission authorization status", async () => {
    const { messages, postToMain } = recordMessages();
    const request = new Uint8Array([9, 10]);
    const calls: {
      productId: string;
      artifactSha256: Uint8Array;
      request: Uint8Array;
      status: PermissionAuthorizationStatus;
    }[] = [];
    const runtime = makeRuntime({
      setPermissionAuthorizationStatus: async (
        productId,
        artifactSha256,
        receivedRequest,
        status,
      ) => {
        calls.push({
          productId,
          artifactSha256,
          request: receivedRequest,
          status,
        });
      },
    });

    await handleSetPermissionAuthorizationStatus(
      runtime,
      postToMain,
      PRODUCT_ID,
      ARTIFACT_SHA256,
      9,
      request,
      "Denied",
    );

    expect(calls).toEqual([
      {
        productId: PRODUCT_ID,
        artifactSha256: ARTIFACT_SHA256,
        request,
        status: "Denied",
      },
    ]);
    expect(messages).toEqual([
      {
        kind: "setPermissionAuthorizationStatusResponse",
        requestId: 9,
        ok: true,
      },
    ]);
  });

  it("reports permission authorization requests received before runtime is ready", async () => {
    const { messages, postToMain } = recordMessages();
    const request = new Uint8Array([1]);

    await handleGetPermissionAuthorizationStatus(
      null,
      postToMain,
      PRODUCT_ID,
      ARTIFACT_SHA256,
      1,
      request,
    );
    await handleGetPermissionAuthorizationStatuses(
      null,
      postToMain,
      PRODUCT_ID,
      ARTIFACT_SHA256,
      2,
      [request],
    );
    await handleSetPermissionAuthorizationStatus(
      null,
      postToMain,
      PRODUCT_ID,
      ARTIFACT_SHA256,
      3,
      request,
      "Authorized",
    );

    expect(messages).toEqual([
      {
        kind: "permissionAuthorizationStatusResponse",
        requestId: 1,
        ok: false,
        error: "permissionAuthorizationStatus received before runtime is ready",
      },
      {
        kind: "permissionAuthorizationStatusesResponse",
        requestId: 2,
        ok: false,
        error:
          "permissionAuthorizationStatuses received before runtime is ready",
      },
      {
        kind: "setPermissionAuthorizationStatusResponse",
        requestId: 3,
        ok: false,
        error:
          "setPermissionAuthorizationStatus received before runtime is ready",
      },
    ]);
  });
});
