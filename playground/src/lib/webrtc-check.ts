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
//   1. requestRemotePermission("WebRtc") — governs whether the container leaves
//      `RTCPeerConnection` in the realm at all;
//   2. requestDevicePermission("Camera") and ("Microphone") — device permissions;
//   3. only once granted, getUserMedia + RTCPeerConnection.createOffer.
//
// The WebRtc decision is resolved by the host before the product realm exists
// and baked into the container, because a permission request made from inside
// that realm would be forgeable by product script. So a first-time grant cannot
// take effect during this run: `RTCPeerConnection` stays absent until the next
// load. Granting and re-running is the expected path, and the reason this method
// cannot pass unattended.

export const WEBRTC_SERVICE_NAME = "WebRTC";
export const WEBRTC_METHOD_NAME = "peer_connection";

const WEBRTC_EXAMPLE_SOURCE = `// Fail fast: WebRTC media capture requires a secure context, so bail before
// prompting for any permission if the origin isn't secure.
console.log("secure context:", window.isSecureContext);
assert(
  window.isSecureContext,
  "Not a secure context — WebRTC media capture requires HTTPS or a localhost/loopback origin.",
);

// Permission phase — the WebRtc remote permission first: it decides whether the
// container leaves RTCPeerConnection in this realm at all.
const webRtc = await truapi.permissions.requestRemotePermission({
  permission: { tag: "WebRtc" },
});
assert(webRtc.isOk(), "WebRTC permission request failed:", webRtc);
assert(webRtc.value.granted, "WebRTC permission denied");
console.log("WebRTC permission granted");

// Then the camera and microphone through TrUAPI.
const camera = await truapi.permissions.requestDevicePermission("Camera");
assert(camera.isOk(), "camera permission request failed:", camera);
assert(camera.value.granted, "camera permission denied");
console.log("camera granted");

const microphone = await truapi.permissions.requestDevicePermission("Microphone");
assert(microphone.isOk(), "microphone permission request failed:", microphone);
assert(microphone.value.granted, "microphone permission denied");
console.log("microphone granted");

// Capability phase — permissions granted, now access the capability.
assert(
  typeof RTCPeerConnection !== "undefined",
  "RTCPeerConnection is unavailable (fail-closed). The container removes it unless " +
    "the WebRtc grant was already in place when this realm loaded, so if you just " +
    "granted it, reload and run again.",
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
        "Requests the WebRtc remote permission plus camera + microphone " +
        "through TrUAPI, then — once granted — opens an RTCPeerConnection and " +
        "creates an offer with the captured media. A first-time WebRtc grant " +
        "only takes effect after a reload.",
      exampleSource: WEBRTC_EXAMPLE_SOURCE,
    },
  ],
};
