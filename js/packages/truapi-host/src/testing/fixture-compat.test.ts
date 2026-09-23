import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { createTestHostFixture, fromNetworks } from "./playwright.js";
import { createMockClient } from "./create-mock-client.js";
import { wasmIsBuilt } from "./require-wasm.js";
import { PASEO_ASSET_HUB, LIVE_CHAINS } from "./dev-accounts.js";

const SAMPLE_CHAIN = {
  id: "paseo-asset-hub",
  name: "Paseo Asset Hub",
  genesisHash: "0x23e730eb",
  rpcUrl: "wss://paseo-asset-hub-next-rpc.polkadot.io",
};

/**
 * The page URL a fixture built with `options` sends the browser to.
 *
 * The expansion is internal, and the fixture returns only its Playwright
 * callback, so the URL is where an accepted-then-dropped `chain` becomes
 * visible. Stopping at `goto` keeps this off a real browser.
 */
async function hostPageUrlFor(
  options: Record<string, unknown>,
): Promise<string> {
  const { testHost } = createTestHostFixture({
    productUrl: "http://localhost:5200",
    hostUrl: "http://localhost:5199",
    ...options,
  } as Parameters<typeof createTestHostFixture>[0]);
  let seen = "";
  const stop = new Error("stop after goto");
  const page = {
    goto: async (url: string) => {
      seen = url;
      throw stop;
    },
  };
  await expect(testHost({ page } as never, async () => {})).rejects.toThrow(
    stop,
  );
  return seen;
}

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
    expect(
      fromNetworks([{ ...SAMPLE_CHAIN, id: "paseo-people" }]).runtimeConfig,
    ).toEqual({ people: { genesisHash: "0x23e730eb" } });
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
    expect(PASEO_ASSET_HUB.id).toBe("paseo-asset-hub");
    const expanded = fromNetworks([PASEO_ASSET_HUB]);
    expect(expanded.runtimeConfig).toEqual({
      assetHub: { genesisHash: LIVE_CHAINS.paseoAssetHub.genesisHash },
    });
  });

  it("derives that hash instead of keeping a copy of it", () => {
    // Comparing the two values cannot fail, because the export is assigned
    // from `LIVE_CHAINS`. What went stale in the old package was a *literal*,
    // so the reference is the thing worth pinning: read the source and refuse
    // a hard-coded hash, which is the only form that can drift.
    const source = readFileSync(
      fileURLToPath(new URL("./dev-accounts.ts", import.meta.url)),
      "utf8",
    );
    const declaration = source.slice(
      source.indexOf("export const PASEO_ASSET_HUB"),
    );
    const assigned = declaration.slice(0, declaration.indexOf("} as const;"));

    expect(assigned).toContain(
      "genesisHash: LIVE_CHAINS.paseoAssetHub.genesisHash",
    );
    expect(assigned).not.toMatch(/genesisHash:\s*"0x/);
  });

  it("accepts `chain` as the older spelling of `networks`", async () => {
    // Roughly half the consumer fleet was written against the vintage that
    // spells this `chain`. Accepting it and then dropping it is the worse
    // failure, because the suite runs against a host with no chain and the
    // error surfaces somewhere else entirely. So assert the expansion, not
    // that the call survived.
    expect(await hostPageUrlFor({ chain: SAMPLE_CHAIN })).toBe(
      await hostPageUrlFor({ networks: [SAMPLE_CHAIN] }),
    );
  });

  it("refuses both `chain` and `networks` rather than guessing", () => {
    expect(() =>
      createTestHostFixture({
        productUrl: "http://localhost:5200",
        chain: SAMPLE_CHAIN,
        networks: [SAMPLE_CHAIN],
      }),
    ).toThrow(/either `chain`.*or `networks`/s);
  });

  it("needs no hostUrl", () => {
    // The server is started lazily by the first test, so construction alone
    // must not require one -- that is the line every consumer gets to delete.
    expect(() =>
      createTestHostFixture({ productUrl: "http://localhost:5200" }),
    ).not.toThrow();
  });
});

describe("proxy routing across several chains", () => {
  const PEOPLE = {
    id: "paseo-people",
    name: "Paseo People",
    genesisHash: "0x4a2b5b73",
    rpcUrl: "wss://paseo-people-next-system-rpc.polkadot.io",
  };

  it("hashes every proxy once there is more than one chain", () => {
    const { mock } = fromNetworks([SAMPLE_CHAIN, PEOPLE]);
    // Both hashed: an unhashed entry takes every request no hashed entry
    // claims, so leaving either one unhashed lets it answer for the other.
    expect(mock.chainProxies).toEqual([
      { genesisHash: SAMPLE_CHAIN.genesisHash, rpcUrl: SAMPLE_CHAIN.rpcUrl },
      { genesisHash: PEOPLE.genesisHash, rpcUrl: PEOPLE.rpcUrl },
    ]);
    // Each chain still has to reach its own endpoint.
    const byHash = new Map(
      (mock.chainProxies ?? []).map((p) => [p.genesisHash, p.rpcUrl]),
    );
    expect(byHash.get(PEOPLE.genesisHash)).toBe(PEOPLE.rpcUrl);
    expect(byHash.get(SAMPLE_CHAIN.genesisHash)).toBe(SAMPLE_CHAIN.rpcUrl);
  });

  it("leaves a lone proxy unhashed, so a chain reset cannot break it", () => {
    const { mock } = fromNetworks([SAMPLE_CHAIN]);
    expect(mock.chainProxies).toEqual([{ rpcUrl: SAMPLE_CHAIN.rpcUrl }]);
  });
});

describe("reading a stored value back the way the old package spelled it", () => {
  // `@parity/host-api-test-sdk` spells this `getProductStorageValue`, returns a
  // string, and publishes it on the in-page host, where a suite compares the
  // result inside a `page.waitForFunction` predicate. All three matter: a
  // promise, or a node-only member, fails such a predicate rather than the
  // assertion under it.
  const suite = wasmIsBuilt("testing/truapi_server.js") ? describe : describe.skip;

  suite("against the real core", () => {
    it("decodes what the product wrote, matching on the product's own key", async () => {
      const { client, host, dispose } = await createMockClient();
      try {
        // "hi" as the hex the generated client takes.
        const written = await client.localStorage.write({
          key: "greeting",
          value: "0x6869",
        });
        expect(written.isOk()).toBe(true);

        // The core namespaced the key before the host saw it, so a suite
        // asking for its own key has to still find the value.
        expect(Object.keys(host.getProductStorage())).not.toContain("greeting");
        expect(host.getProductStorageValue("greeting")).toBe("hi");
      } finally {
        dispose();
      }
    });

    it("keeps a prefixed store distinct from an unprefixed one", async () => {
      // A product writing `demo:mykey` and `mykey` produces two namespaced keys
      // that both end in `:mykey`. A suffix search answers either with whichever
      // it reaches first, so a suite asserting the two stores do not collide
      // passes whatever the host does. This is that assertion.
      const { client, host, dispose } = await createMockClient();
      try {
        // "hi" and "jj" as the hex the generated client takes.
        await client.localStorage.write({ key: "demo:mykey", value: "0x6869" });
        await client.localStorage.write({ key: "mykey", value: "0x6a6a" });

        expect(host.getProductStorageValue("demo:mykey")).toBe("hi");
        expect(host.getProductStorageValue("mykey")).toBe("jj");
      } finally {
        dispose();
      }
    });

    it("does not answer a bare key with a prefixed entry", async () => {
      const { client, host, dispose } = await createMockClient();
      try {
        await client.localStorage.write({ key: "demo:only", value: "0x6869" });
        expect(host.getProductStorageValue("only")).toBeUndefined();
      } finally {
        dispose();
      }
    });

    it("returns synchronously, not a promise", async () => {
      const { host, dispose } = await createMockClient();
      try {
        expect(host.getProductStorageValue("greeting")).not.toBeInstanceOf(
          Promise,
        );
      } finally {
        dispose();
      }
    });

    it("keeps a key the product never wrote undefined", async () => {
      const { host, dispose } = await createMockClient();
      try {
        // Not an empty string: "stored nothing" and "stored nothing here" are
        // different claims, and a suite asserting a cleared key wants the latter.
        expect(host.getProductStorageValue("never-written")).toBeUndefined();
      } finally {
        dispose();
      }
    });
  });
});

describe("where the loopback statement store attaches", () => {
  const PEOPLE = {
    id: "paseo-people",
    name: "Paseo People",
    genesisHash: "0xpeople",
    rpcUrl: "wss://people.example",
  };

  it("serves the store on the only chain when no People chain is declared", () => {
    // A suite declaring a hub alone still has to be able to publish: its single
    // proxy is unhashed, so it takes the statement requests too. Without this
    // the statements reach the hub, which has no store, and the suite waits out
    // its timeout with nothing to show for it.
    const { mock } = fromNetworks([SAMPLE_CHAIN], true);
    expect(mock.chainProxies).toEqual([
      { rpcUrl: SAMPLE_CHAIN.rpcUrl, loopbackStatements: true },
    ]);
  });

  it("serves it only on People when one is declared", () => {
    const { mock } = fromNetworks([SAMPLE_CHAIN, PEOPLE], true);
    expect(mock.chainProxies).toEqual([
      { genesisHash: SAMPLE_CHAIN.genesisHash, rpcUrl: SAMPLE_CHAIN.rpcUrl },
      {
        genesisHash: PEOPLE.genesisHash,
        rpcUrl: PEOPLE.rpcUrl,
        loopbackStatements: true,
      },
    ]);
  });

  it("refuses several chains with no People among them, rather than silently serving nothing", () => {
    const second = { ...SAMPLE_CHAIN, id: "paseo-bulletin", genesisHash: "0xb" };
    expect(() => fromNetworks([SAMPLE_CHAIN, second], true)).toThrow(
      /needs a People chain/,
    );
  });

  it("attaches nothing when the store is not asked for", () => {
    const { mock } = fromNetworks([SAMPLE_CHAIN], false);
    expect(mock.chainProxies).toEqual([{ rpcUrl: SAMPLE_CHAIN.rpcUrl }]);
  });
});

describe("the permission policy the old package's name asks for", () => {
  const suite = wasmIsBuilt("testing/truapi_server.js") ? describe : describe.skip;

  suite("against the real core", () => {
    it("takes `reject-all` without complaint", async () => {
      // Both spellings denied before this, but only by accident: `granted`
      // compares against "allow-all", so every other string fell through to a
      // denial. What changed is that the name is now recognised rather than
      // merely unequal -- which is what makes the check below possible.
      const { host, dispose } = await createMockClient();
      try {
        expect(() => host.setPermissionBehavior("reject-all")).not.toThrow();
      } finally {
        dispose();
      }
    });

    it("refuses a policy name that means nothing here", async () => {
      // This is the case the accident hid: a typo denied everything silently,
      // and a suite meaning to allow saw refusals with nothing saying why.
      const { host, dispose } = await createMockClient();
      try {
        expect(() =>
          (host.setPermissionBehavior as (value: string) => void)("allow_all"),
        ).toThrow(/does not know the policy/);
      } finally {
        dispose();
      }
    });
  });
});
