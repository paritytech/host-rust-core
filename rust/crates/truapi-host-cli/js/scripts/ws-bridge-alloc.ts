/// <reference path="../runner.ts" />
// Allocate every resource and print the outcomes with a wall-clock time.
//
// Run this through the localhost WebSocket bridge (`--ws-bridge`) rather than the
// frame socket. That transport is the one piece of the native mobile path the CLI
// otherwise cannot exercise: the allocation logic and chain access are shared
// with the frame transport, so a fault that appears only here is the bridge.
//
// The comparison that matters is dotli, where the signing host produced an
// allocation response after 147s and the browser never received it.
export {};

const started = Date.now();

const login = await truapi.account.requestLogin({ reason: undefined });
if (
  !login.isOk() ||
  (login.value !== "Success" && login.value !== "AlreadyConnected")
) {
  throw new Error(
    `requestLogin failed: ${login.isOk() ? login.value : JSON.stringify(login.error)}`,
  );
}

const result = await truapi.resourceAllocation.request({
  resources: [
    { tag: "StatementStoreAllowance" },
    { tag: "BulletinAllowance" },
    { tag: "SmartContractAllowance", value: { tag: "Index", value: 0 } },
    { tag: "AutoSigning" },
  ],
});

const elapsed = ((Date.now() - started) / 1000).toFixed(1);
if (!result.isOk()) {
  throw new Error(
    `allocation failed after ${elapsed}s: ${JSON.stringify(result.error)}`,
  );
}

console.log(`WS_BRIDGE_ALLOC_OK ${elapsed}s outcomes=${result.value.outcomes.join(",")}`);
