/// <reference path="../runner.ts" />
import { PASEO_NEXT_V2_INDIVIDUALITY } from "../../../../../js/packages/truapi/src/index.ts";
// Phase A of the cross-product check (dim2-spa#53 groundwork): run the host as
// `peopl.dot` and register a lite-ring ring-VRF key in its domain. Phase B
// reconnects the SAME session as `dim2.dot` and tries to use this key.
export {};

const PEOPLE_LITE_COLLECTION =
  "0x706f703a706f6c6b61646f742e6e6574776f726b2f70656f706c652d6c697465";
const PEOPLE_GENESIS = PASEO_NEXT_V2_INDIVIDUALITY.genesis;

if (host.productId !== "peopl.dot")
  throw new Error(`phase A must run with --product-id peopl.dot, got ${host.productId}`);

// RFC-0022 pins index 1 as the light person key.
const index = { tag: "Index" as const, value: 1 };
const ringLocation = {
  chainId: PEOPLE_GENESIS as `0x${string}`,
  junctions: [
    { tag: "CollectionId" as const, value: PEOPLE_LITE_COLLECTION as `0x${string}` },
  ],
};

const login = await truapi.account.requestLogin({ reason: undefined });
assert(
  login.isOk() && (login.value === "Success" || login.value === "AlreadyConnected"),
  `requestLogin failed: ${JSON.stringify(login)}`,
);

const registration = await truapi.account.registerRingVrfKey({ index, ring: ringLocation });
assert(registration.isOk(), `registerRingVrfKey failed: ${JSON.stringify(registration)}`);

// Owner can sign with its own key straight away.
const signature = await truapi.account.ringVrfSign({
  keyHandle: { dotNsIdentifier: "peopl.dot", derivationIndex: index },
  message: "0x64696d322d726663323478", // "dim2-rfc24x"
});
assert(signature.isOk(), `owner ringVrfSign failed: ${JSON.stringify(signature)}`);

console.log(`PHASE_A_OK publicKey=${registration.value} ownerSig=${signature.value}`);
