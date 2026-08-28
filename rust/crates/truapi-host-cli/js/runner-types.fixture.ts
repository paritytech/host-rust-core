/// <reference path="./script-types.d.ts" />
export {};

const productContext = await truapi.system.getProductContext();
if (productContext.isOk()) {
  const productId: string = productContext.value.productId;
  assert(productId.length > 0);

  // @ts-expect-error Product context does not contain the signed-in user.
  productContext.value.userId;
}

const account = host.productAccount(0);
const accountProductId: string = account.dotNsIdentifier;
assert(accountProductId.length > 0);

// @ts-expect-error Product accounts have no user-facing username.
account.username;

// @ts-expect-error Derivation indices are numeric.
host.productAccount("0");

// @ts-expect-error The generated client rejects unknown services.
truapi.unknownService;
