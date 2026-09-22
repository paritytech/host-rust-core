import {
  scale,
  VersionedRemotePermissionRequest,
  VersionedRemotePermissionResponse,
  VersionedRemotePermissionError,
  VersionedHostDevicePermissionRequest,
  VersionedHostDevicePermissionResponse,
  VersionedHostDevicePermissionError,
  type RemotePermission,
  type TrUApiTransport,
} from "../../../../js/packages/truapi/src/index.ts";
import {
  PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION,
  PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION,
} from "../../../../js/packages/truapi/src/generated/wire-table.ts";
import type { PermissionAuthorization } from "../../../../js/container/src/container.ts";

export function createCliAuthorization(
  transport: TrUApiTransport,
): PermissionAuthorization {
  function authorize(
    operation: (signal: AbortSignal) => Promise<boolean>,
    decide: (allowed: boolean) => void,
  ): () => void {
    const controller = new AbortController();
    const finish = (allowed: boolean) => {
      if (!controller.signal.aborted) decide(allowed);
    };
    operation(controller.signal).then(finish, () => finish(false));
    return () => controller.abort();
  }

  const remote = (permission: RemotePermission, signal: AbortSignal) =>
    transport
      .request({
        ids: PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION,
        payload: VersionedRemotePermissionRequest.enc({
          tag: "V1",
          value: { permission },
        }),
        decodeResponse: scale.Result(
          VersionedRemotePermissionResponse,
          scale.CallError(VersionedRemotePermissionError),
        ).dec,
        signal,
      })
      .match(
        (response) => response.value.granted,
        () => false,
      );

  const device = (permission: "Camera" | "Microphone", signal: AbortSignal) =>
    transport
      .request({
        ids: PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION,
        payload: VersionedHostDevicePermissionRequest.enc({
          tag: "V1",
          value: permission,
        }),
        decodeResponse: scale.Result(
          VersionedHostDevicePermissionResponse,
          scale.CallError(VersionedHostDevicePermissionError),
        ).dec,
        signal,
      })
      .match(
        (response) => response.value.granted,
        () => false,
      );

  return {
    network: (url, decide) =>
      authorize(async (signal) => {
        const { hostname, protocol } = new URL(url);
        if (
          !hostname ||
          hostname.includes("*") ||
          !["http:", "https:", "ws:", "wss:"].includes(protocol)
        )
          return false;
        return remote(
          { tag: "Remote", value: { domains: [hostname] } },
          signal,
        );
      }, decide),
    webRtc: (decide) =>
      authorize(async (signal) => remote({ tag: "WebRtc" }, signal), decide),
    media: (audio, video, decide) =>
      authorize(async (signal) => {
        if (video && !(await device("Camera", signal))) return false;
        return audio ? device("Microphone", signal) : video;
      }, decide),
  };
}
