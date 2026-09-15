import { describe, expect, it } from "bun:test";

import { createTestHostFixture, fromNetworks } from "./playwright.js";
import { PASEO_ASSET_HUB, LIVE_CHAINS } from "./dev-accounts.js";

const SAMPLE_CHAIN = {
  id: "paseo-asset-hub",
  name: "Paseo Asset Hub",
  genesisHash: "0x23e730eb",
  rpcUrl: "wss://paseo-asset-hub-next-rpc.polkadot.io",
};

describe("host-api-test-sdk option compatibility", () => {
  it("expands `networks` into the three settings that must agree", () => {
    const { mock, runtimeConfig } = fromNetworks([SAMPLE_CHAIN]);
    expect(mock.supportedChains).toEqual({
      network: "paseo",
      chains: [{ identifier: "AssetHub", genesisHash: "0x23e730eb" }],
    });
    // Unhashed on purpose: an unhashed proxy takes every request, so routing
    // survives a chain reset even when the declared hash goes stale.
    expect(mock.chainProxies).toEqual([{ rpcUrl: SAMPLE_CHAIN.rpcUrl }]);
    expect(runtimeConfig).toEqual({ assetHub: { genesisHash: "0x23e730eb" } });
  });

  it("reads the chain's role from the id suffix", () => {
    expect(fromNetworks([{ ...SAMPLE_CHAIN, id: "paseo-people" }]).runtimeConfig)
      .toEqual({ people: { genesisHash: "0x23e730eb" } });
    const relay = fromNetworks([{ ...SAMPLE_CHAIN, id: "previewnet" }]);
    expect(relay.mock.supportedChains).toEqual({
      network: "previewnet",
      chains: [{ identifier: "Relay", genesisHash: "0x23e730eb" }],
    });
    // The runtime config has no relay slot, so there is nothing to declare.
    expect(relay.runtimeConfig).toEqual({});
  });

  it("rejects a pinned product account, and says why", () => {
    expect(() =>
      createTestHostFixture({
        productUrl: "http://localhost:5200",
        productAccounts: { "signer-demo.dot/0": "bob" },
      }),
    ).toThrow(/DERIVED from \(session root, product id\)/);
  });

  it("rejects a derivation uri, and says what to use instead", () => {
    expect(() =>
      createTestHostFixture({
        productUrl: "http://localhost:5200",
        accounts: [{ name: "alice", uri: "//Alice" }],
      }),
    ).toThrow(/32 bytes of BIP-39 entropy/);
  });

  it("accepts plain names and name-only objects", () => {
    expect(() =>
      createTestHostFixture({
        productUrl: "http://localhost:5200",
        accounts: ["bob", { name: "charlie" }],
      }),
    ).not.toThrow();
  });

  it("exports PASEO_ASSET_HUB, carrying the hash we actually proxy to", () => {
    // The old package's copy went stale across a chain reset. A suite that
    // migrates by keeping `networks: [PASEO_ASSET_HUB]` must get the live one,
    // or the product's descriptor check fails on a genesis mismatch.
    expect(PASEO_ASSET_HUB.genesisHash).toBe(
      LIVE_CHAINS.paseoAssetHub.genesisHash,
    );
    expect(PASEO_ASSET_HUB.id).toBe("paseo-asset-hub");
    const expanded = fromNetworks([PASEO_ASSET_HUB]);
    expect(expanded.runtimeConfig).toEqual({
      assetHub: { genesisHash: LIVE_CHAINS.paseoAssetHub.genesisHash },
    });
  });

  it("needs no hostUrl", () => {
    // The server is started lazily by the first test, so construction alone
    // must not require one -- that is the line every consumer gets to delete.
    expect(() =>
      createTestHostFixture({ productUrl: "http://localhost:5200" }),
    ).not.toThrow();
  });
});
