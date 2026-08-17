import type { ServiceInfo } from "@parity/truapi/playground/services-types";

// A first-class playground method backed by an example that combines TrUAPI
// permission calls with the browser WebRTC APIs. It runs through the same
// example runner as every other method (`truapi` and `assert`/`console` are
// injected; globals like `navigator`/`RTCPeerConnection` are reachable in the
// runner's function scope), so it shows up in the method browser, ⌘K, and the
// diagnosis alike.
//
// The example follows the product model — request every permission via TrUAPI
// first, then use the capability:
//   1. requestDevicePermission("Camera") and ("Microphone") — device permissions;
//   2. requestRemotePermission({ permission: { tag: "WebRtc" } }) — remote permission;
//   3. only once granted, getUserMedia + RTCPeerConnection.createOffer.

export const WEBRTC_SERVICE_NAME = "WebRTC";
export const WEBRTC_METHOD_NAME = "peer_connection";

const WEBRTC_EXAMPLE_SOURCE = `// Fail fast: WebRTC media capture requires a secure context, so bail before
// prompting for any permission if the origin isn't secure.
console.log("secure context:", window.isSecureContext);
assert(
  window.isSecureContext,
  "Not a secure context — WebRTC media capture requires HTTPS or a localhost/loopback origin.",
);

// Permission phase — request every permission through TrUAPI up front.
const camera = await truapi.permissions.requestDevicePermission("Camera");
assert(camera.isOk(), "camera permission request failed:", camera);
assert(camera.value.granted, "camera permission denied");
console.log("camera granted");

const microphone = await truapi.permissions.requestDevicePermission("Microphone");
assert(microphone.isOk(), "microphone permission request failed:", microphone);
assert(microphone.value.granted, "microphone permission denied");
console.log("microphone granted");

const webrtc = await truapi.permissions.requestRemotePermission({
  permission: { tag: "WebRtc" },
});
assert(webrtc.isOk(), "WebRTC permission request failed:", webrtc);
assert(webrtc.value.granted, "WebRTC permission denied");
console.log("WebRTC granted");

// Capability phase — permissions granted, now access the capability.
assert(
  typeof RTCPeerConnection !== "undefined",
  "RTCPeerConnection is unavailable — the host has not wired the WebRTC bridge (fail-closed).",
);
assert(
  typeof navigator !== "undefined" && !!navigator.mediaDevices?.getUserMedia,
  "navigator.mediaDevices.getUserMedia is unavailable in this host.",
);

const stream = await navigator.mediaDevices.getUserMedia({
  video: true,
  audio: true,
});
console.log(
  "media captured:",
  stream.getTracks().map((t) => t.kind).join(", "),
);

const pc = new RTCPeerConnection();
try {
  for (const track of stream.getTracks()) pc.addTrack(track, stream);
  const offer = await pc.createOffer();
  assert(!!offer.sdp, "createOffer returned an empty SDP");
  console.log("offer created:", offer.type, offer.sdp.length + " bytes of SDP");
} finally {
  pc.close();
  stream.getTracks().forEach((t) => t.stop());
}`;

/** Synthetic WebRTC method — browsable, runnable, and part of the diagnosis. */
export const WEBRTC_SERVICE: ServiceInfo = {
  name: WEBRTC_SERVICE_NAME,
  methods: [
    {
      name: WEBRTC_METHOD_NAME,
      type: "unary",
      description:
        "Requests camera + microphone (device permissions) and WebRTC (remote " +
        "permission) through TrUAPI, then — once granted — opens an " +
        "RTCPeerConnection and creates an offer with the captured media.",
      exampleSource: WEBRTC_EXAMPLE_SOURCE,
    },
  ],
};
