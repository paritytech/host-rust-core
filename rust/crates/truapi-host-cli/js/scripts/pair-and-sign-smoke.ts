/// <reference path="../runner.ts" />
export {};

const login = await truapi.account.requestLogin({ reason: undefined });
if (
  !login.isOk() ||
  (login.value !== "Success" && login.value !== "AlreadyConnected")
) {
  throw new Error(
    `requestLogin failed: ${login.isOk() ? login.value : JSON.stringify(login.error)}`,
  );
}

const signature = await truapi.signing.signRaw({
  account: host.productAccount(),
  payload: { tag: "Bytes", value: { bytes: "0xdeadbeef" } },
});
if (!signature.isOk()) {
  throw new Error(`signRaw failed: ${JSON.stringify(signature.error)}`);
}

console.log("PAIR_AND_SIGN_OK");
