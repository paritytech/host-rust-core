import { describe, expect, test } from "bun:test";

import {
  createRingProverParamsLoader,
  type RingProverParamsManifest,
} from "./ring-prover-params.js";

const DOMAIN11 = new Uint8Array([0]);
const DOMAIN12 = new Uint8Array([1]);
const DOMAIN16 = new Uint8Array([2]);

const MANIFEST: RingProverParamsManifest = {
  domain11: { file: "srs-domain11-7a73571d.bin", blake2b256: "7a73", bytes: 4 },
  domain12: { file: "srs-domain12-cfaef391.bin", blake2b256: "cfae", bytes: 4 },
};

describe("ring prover params loader", () => {
  test("reads nothing until a domain is asked for, then once per domain", async () => {
    const fetched: string[] = [];
    let manifests = 0;
    const load = createRingProverParamsLoader({
      loadManifest: async () => {
        manifests += 1;
        return MANIFEST;
      },
      fetchBytes: async (file) => {
        fetched.push(file);
        return new Uint8Array([1, 2, 3, 4]);
      },
    });

    expect(manifests).toBe(0);
    expect(fetched).toEqual([]);

    expect(await load(DOMAIN11)).toEqual(new Uint8Array([1, 2, 3, 4]));
    expect(await load(DOMAIN11)).toEqual(new Uint8Array([1, 2, 3, 4]));
    expect(await load(DOMAIN12)).toEqual(new Uint8Array([1, 2, 3, 4]));

    expect(fetched).toEqual([
      "srs-domain11-7a73571d.bin",
      "srs-domain12-cfaef391.bin",
    ]);
    expect(manifests).toBe(1);
  });

  test("concurrent requests for one domain share a single read", async () => {
    let fetches = 0;
    const load = createRingProverParamsLoader({
      loadManifest: async () => MANIFEST,
      fetchBytes: async () => {
        fetches += 1;
        return new Uint8Array([7]);
      },
    });

    const [first, second] = await Promise.all([
      load(DOMAIN11),
      load(DOMAIN11),
    ]);

    expect(first).toEqual(new Uint8Array([7]));
    expect(second).toEqual(new Uint8Array([7]));
    expect(fetches).toBe(1);
  });

  test("a domain the manifest does not carry resolves to undefined", async () => {
    const load = createRingProverParamsLoader({
      loadManifest: async () => MANIFEST,
      fetchBytes: async () => {
        throw new Error("must not read a file the manifest does not name");
      },
    });

    expect(await load(DOMAIN16)).toBeUndefined();
  });

  test("an unknown domain tag resolves to undefined without reading", async () => {
    const load = createRingProverParamsLoader({
      loadManifest: async () => {
        throw new Error("must not read the manifest for an unknown domain");
      },
      fetchBytes: async () => new Uint8Array(),
    });

    expect(await load(new Uint8Array([9]))).toBeUndefined();
  });

  test("a failed read is retried rather than remembered as an absence", async () => {
    let attempts = 0;
    const load = createRingProverParamsLoader({
      loadManifest: async () => MANIFEST,
      fetchBytes: async () => {
        attempts += 1;
        if (attempts === 1) throw new Error("offline");
        return new Uint8Array([5]);
      },
    });

    await expect(load(DOMAIN11)).rejects.toThrow("offline");
    expect(await load(DOMAIN11)).toEqual(new Uint8Array([5]));
    expect(attempts).toBe(2);
  });
});
