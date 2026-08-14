/// <reference path="../runner.ts" />
export {};

// The script is the product, so it logs in first. Allocation begins with
// `require_current_session`, and without this a host with no session yet fails with
// "resource allocation failed", which points away from the real cause.
const login = await truapi.account.requestLogin({ reason: undefined });
if (
  !login.isOk() ||
  (login.value !== "Success" && login.value !== "AlreadyConnected")
) {
  throw new Error(
    `requestLogin failed: ${login.isOk() ? login.value : JSON.stringify(login.error)}`,
  );
}

// A PGAS allowance credits the product account the derivation index names, so this
// asks for index 0.
const index = { tag: "Index" as const, value: 0 };

// Whether the host serves Asset Hub decides which outcome is correct, so ask it
// rather than accepting either. Without this the check passes on any failure: the
// host maps every claim error to `NotAvailable`.
const assetHub = await truapi.chain.getChainInfo({ chain: "AssetHub" });
const servesAssetHub = assetHub.isOk();
console.log(
  servesAssetHub
    ? `host serves Asset Hub at ${assetHub.value.genesisHash}`
    : "host serves no Asset Hub role",
);

const result = await truapi.resourceAllocation.request({
  resources: [{ tag: "SmartContractAllowance", value: index }],
});
assert(result.isOk(), "resource allocation failed:", result);
assert(
  result.value.outcomes.length === 1,
  "expected one outcome:",
  result.value,
);

const [outcome] = result.value.outcomes;
console.log("smart-contract allowance outcome:", outcome);

if (servesAssetHub) {
  // The claim has to succeed. Accepting `NotAvailable` here would make every
  // failure — an unreachable chain, a rejected proof, a spent day of slots — look
  // the same as a host that simply does not offer PGAS.
  assert(
    outcome === "Allocated",
    "host serves Asset Hub, so the PGAS claim should have been allocated:",
    result.value,
  );
  console.log("PGAS allowance allocated for derivation index 0");
} else {
  assert(
    outcome === "NotAvailable",
    "host serves no Asset Hub role, so PGAS should be unavailable:",
    result.value,
  );
  console.log("PGAS reported unavailable, which matches the served chain set");
}
