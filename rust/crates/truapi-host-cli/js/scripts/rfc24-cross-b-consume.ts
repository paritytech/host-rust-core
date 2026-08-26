/// <reference path="../runner.ts" />
import { PASEO_NEXT_V2_INDIVIDUALITY } from "../../../../../js/packages/truapi/src/index.ts";
// Phase B of the cross-product check: same wallet session, now serving
// `dim2.dot`. Tries to consume the peopl.dot key registered in phase A —
// listing, alias, proof and direct signing — and records exactly which door
// is open, prompted, or shut. Then proves the owner-side braid: register our
// own key and produce a member-key signature (the bytes a registration
// extrinsic would carry via createTransaction).
export {};

const PEOPLE_LITE_COLLECTION =
  "0x706f703a706f6c6b61646f742e6e6574776f726b2f70656f706c652d6c697465";
const PEOPLE_GENESIS = PASEO_NEXT_V2_INDIVIDUALITY.genesis;

if (host.productId !== "dim2.dot")
  throw new Error(`phase B must run with --product-id dim2.dot, got ${host.productId}`);

const foreignHandle = {
  dotNsIdentifier: "peopl.dot",
  derivationIndex: { tag: "Index" as const, value: 1 },
};
const ringLocation = {
  chainId: PEOPLE_GENESIS as `0x${string}`,
  junctions: [
    { tag: "CollectionId" as const, value: PEOPLE_LITE_COLLECTION as `0x${string}` },
  ],
};
const context = {
  productId: "dim2.dot",
  suffix: { tag: "Index" as const, value: 0 },
};
const message = "0x64696d322d726663323478";

const login = await truapi.account.requestLogin({ reason: undefined });
assert(
  login.isOk() && (login.value === "Success" || login.value === "AlreadyConnected"),
  `requestLogin failed: ${JSON.stringify(login)}`,
);

const outcomes: string[] = [];
const record = (label: string, result: { isOk(): boolean; value?: unknown; error?: unknown }) => {
  const detail = result.isOk()
    ? `OK ${JSON.stringify(result.value).slice(0, 80)}`
    : `ERR ${JSON.stringify(result.error)}`;
  outcomes.push(`${label}: ${detail}`);
  console.log(`X_PRODUCT ${label}: ${detail}`);
};

// 1. Can dim2 even see peopl.dot's registry entries?
record(
  "list(anonymized)",
  await truapi.account.listRingVrfKeys({ owner: "peopl.dot", disclosure: "Anonymized" }),
);
record(
  "list(publicKey)",
  await truapi.account.listRingVrfKeys({ owner: "peopl.dot", disclosure: "PublicKey" }),
);

// 2. Alias with the foreign key (RFC: consent prompt allowed).
record(
  "getAccountAlias(foreign)",
  await truapi.account.getAccountAlias({ keyHandle: foreignHandle, context, ringLocation }),
);

// 3. Proof with the foreign key (RFC: allowlist only, no prompt).
record(
  "createAccountProof(foreign)",
  await truapi.account.createAccountProof({
    keyHandle: foreignHandle,
    context,
    ringLocation,
    message,
  }),
);

// 4. Direct signature with the foreign key (RFC: allowlist only).
record(
  "ringVrfSign(foreign)",
  await truapi.account.ringVrfSign({ keyHandle: foreignHandle, message }),
);

// 5. Owner-side braid: dim2 registers its own key and signs — these bytes are
//    what a registration extrinsic would carry through createTransaction.
const ownIndex = { tag: "Index" as const, value: 1 };
const ownRegistration = await truapi.account.registerRingVrfKey({
  index: ownIndex,
  ring: ringLocation,
});
assert(ownRegistration.isOk(), `own registerRingVrfKey failed: ${JSON.stringify(ownRegistration)}`);
const ownSig = await truapi.account.ringVrfSign({
  keyHandle: { dotNsIdentifier: "dim2.dot", derivationIndex: ownIndex },
  message,
});
assert(ownSig.isOk(), `own ringVrfSign failed: ${JSON.stringify(ownSig)}`);

console.log(`PHASE_B_DONE ownPublicKey=${ownRegistration.value} ownSig=${ownSig.value}`);
