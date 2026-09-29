import { describe, expect, it } from "bun:test";

import { productAccountAddress } from "./product-account.js";
import { wasmIsBuilt } from "./require-wasm.js";

const suite = wasmIsBuilt("testing/truapi_server.js") ? describe : describe.skip;

suite("the address a product account will be given", () => {
  // Captured from the running products: `product-sdk`'s contracts-demo and
  // tx-demo reported these after connecting to a host whose session was
  // activated from the `bob` dev account. Pinned as literals because the point
  // of deriving here is to get the same answer a host will, and a derivation
  // checked only against itself would agree with a host that disagreed.
  const CONTRACTS = "5DkXL5QxHcJV4mzcEfScZuS7HJYFzGVJHB1x3m8pLcwpBgja";
  const TX = "5GWoDJDcE2k6LV1aA2wntxwZf9DbES4Tq8423jDA333KqoG3";

  it("matches what a host gives the product", async () => {
    expect(
      await productAccountAddress({
        account: "bob",
        productId: "contracts-demo.dot",
      }),
    ).toBe(CONTRACTS);
    expect(
      await productAccountAddress({ account: "bob", productId: "tx-demo.dot" }),
    ).toBe(TX);
  });

  it("gives each product its own account", async () => {
    // The product id is an input to the derivation, so one account's products
    // do not share a balance -- which is why funding is per (product, account).
    const contracts = await productAccountAddress({
      account: "bob",
      productId: "contracts-demo.dot",
    });
    const tx = await productAccountAddress({
      account: "bob",
      productId: "tx-demo.dot",
    });
    expect(contracts).not.toBe(tx);
  });

  it("gives each session root its own account", async () => {
    // The root is an input to the derivation, so the same product under a
    // different account is a different address -- which is why funding is per
    // (product, account) rather than per product.
    const asCharlie = await productAccountAddress({
      account: "charlie",
      productId: "contracts-demo.dot",
    });
    expect(asCharlie).not.toBe(CONTRACTS);
  });

  it("gives each index its own account", async () => {
    const second = await productAccountAddress({
      account: "bob",
      productId: "contracts-demo.dot",
      index: 1,
    });
    expect(second).not.toBe(CONTRACTS);
  });
});
