// Proves the one-liner actually carries a call: product client -> real core ->
// mock host, over a real MessagePort, with the result observable on the mock.
import { describe, expect, it } from "bun:test";

import { createMockClient } from "./create-mock-client.js";
import { wasmIsBuilt } from "./require-wasm.js";

const suite = wasmIsBuilt("testing/truapi_server.js") ? describe : describe.skip;

suite("createMockClient", () => {
  it("round-trips a product call to the mock host", async () => {
    const { client, host, dispose } = await createMockClient();
    try {
      const result = await client.system.navigateTo({
        url: "https://polkadot.network/",
      });
      expect(result.isOk()).toBe(true);

      // The call reached the host seam, not just the client.
      expect(host.getNavigationLog()).toEqual(["https://polkadot.network/"]);
      expect(host.getHostCallCount()).toBeGreaterThan(0);
    } finally {
      dispose();
    }
  });

  it("round-trips product storage through the real dispatcher", async () => {
    const { client, host, dispose } = await createMockClient();
    try {
      const written = await client.localStorage.write({
        key: "greeting",
        value: "0x6869",
      });
      expect(written.isOk()).toBe(true);

      const read = await client.localStorage.read({ key: "greeting" });
      expect(read.isOk()).toBe(true);
      expect(read._unsafeUnwrap().value).toBe("0x6869");

      // And the host saw it, under the core's namespaced key.
      const stored = Object.entries(host.getProductStorage());
      expect(stored.length).toBeGreaterThan(0);
      expect(stored.some(([key]) => key.endsWith(":greeting"))).toBe(true);
    } finally {
      dispose();
    }
  });

  it("answers a permission prompt from the mock's policy, once", async () => {
    const { client, host, dispose } = await createMockClient({
      mock: { devicePermissions: "deny-all" },
    });
    try {
      const denied = await client.permissions.requestDevicePermission("Camera");
      expect(denied._unsafeUnwrap().granted).toBe(false);
      expect(host.getPermissionLog()).toEqual([
        { tag: "Camera", value: "Camera", approved: false, kind: "device" },
      ]);

      // The core caches a decided authorization, so flipping the host's answer
      // does NOT change an already-decided permission: the second call never
      // reaches the host at all. Pinning that here because it is the behaviour
      // that breaks a test expecting a mid-run grant to take effect.
      host.grantPermission("Camera");
      const again = await client.permissions.requestDevicePermission("Camera");
      expect(again._unsafeUnwrap().granted).toBe(false);
      expect(
        host.getPermissionLog(),
        "a decided permission must not re-prompt the host",
      ).toHaveLength(1);
    } finally {
      dispose();
    }
  });
});
