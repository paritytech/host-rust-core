/// <reference path="../runner.ts" />
export {};

// A PGAS allowance credits the product account the derivation index names, so this
// asks for index 0 and then reads that account's balance back through the host.
const index = { tag: "Index" as const, value: 0 };

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

// `NotAvailable` is the honest answer on a host that serves no Asset Hub, so this
// distinguishes "the host cannot" from "the host tried and failed".
assert(
  outcome !== "Rejected",
  "an optional allocation should never be rejected:",
  result.value,
);
if (outcome === "NotAvailable") {
  console.log(
    "host reports no PGAS support; it serves no Asset Hub role or the claim could not run",
  );
} else {
  assert(outcome === "Allocated", "unexpected outcome:", outcome);
  console.log("PGAS allowance allocated for derivation index 0");
}
