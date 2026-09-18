// The JS mock host and the Rust `MockPlatform` are siblings: both implement the
// same host seam, one for browser tests against the WASM core and one for Rust
// tests against the native core. A capability added to one and forgotten on the
// other is exactly the drift this mock exists to remove, and it is invisible to
// `tsc` because the two surfaces share no types.
//
// So the agreement is asserted here, against the Rust source, in both
// directions. Adding a control method to `mock.rs` without adding it to
// `createMockHost` fails, and so does adding one to `createMockHost` that has
// no Rust sibling and no entry in `JS_ONLY`.
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { createMockHost } from "./create-mock-host.js";

const MOCK_RS = fileURLToPath(
  new URL(
    "../../../../../rust/crates/truapi-platform/src/mock.rs",
    import.meta.url,
  ),
);

/**
 * Rust names that map to a deliberately different JS name.
 *
 * The JS surface matches `@parity/host-api-test-sdk`'s `TestHostAPI` so the
 * suites migrating off it need no edits, while the Rust surface stays
 * idiomatic -- Rust APIs do not prefix readers with `get_`. Every intentional
 * divergence is listed here, so an *unintentional* one still fails the check.
 */
const ALIASES: Record<string, string> = {
  navigations: "getNavigationLog",
  clear_navigations: "clearNavigationLog",
  pushed_notifications: "getNotificationLog",
  clear_notifications: "clearNotificationLog",
  permission_log: "getPermissionLog",
  granted_permissions: "getGrantedPermissions",
  insert_preimage: "seedPreimage",
  preimages: "getPreimages",
  clear_reviews: "clearSigningLog",
  theme: "getTheme",
  chain_status: "getChainStatus",
  chat_rooms: "getChatRooms",
  chat_bots: "getChatBots",
  posted_chat_messages: "getChatMessageLog",
  product_storage: "getProductStorage",
};

/**
 * JS members the Rust mock deliberately has no sibling for, and why.
 *
 * Without this, walking JS -> Rust would fail on every one of them and the
 * direction would have to be dropped. With it, a JS-only control method is a
 * decision someone writes down rather than something that appears silently.
 */
const JS_ONLY: Record<string, string> = {
  callbacks: "the host seam the core calls, not a control surface",
  dispose: "lifecycle, not state; `reset` is what clears the recordings",
  getHostCallCount: "host-api-test-sdk readiness signal, no Rust caller",
  getIsAuthenticated: "host-api-test-sdk reader over the auth-state log",
  getConnectionStatus: "host-api-test-sdk alias over the chain status",
  getSigningLog: "host-api-test-sdk shape over the confirmation reviews",
  setPermissionBehavior:
    "host-api-test-sdk name for the policy Rust sets through MockConfig",
  statements: "loopback statement store, refused on both sides",
  getSubmittedStatements: "loopback statement store, refused on both sides",
  getInjectedStatements: "loopback statement store, refused on both sides",
  injectStatement: "loopback statement store, refused on both sides",
  clearStatements: "loopback statement store, refused on both sides",
  payment: "unimplemented by every host; the mock refuses and explains",
  coinPayment: "unimplemented by every host; the mock refuses and explains",
};

/** snake_case -> camelCase, unless the name is an explicit alias. */
function jsName(name: string): string {
  return (
    ALIASES[name] ??
    name.replace(/_([a-z])/g, (_, letter: string) => letter.toUpperCase())
  );
}

/**
 * Control-surface methods on the Rust `MockPlatform`.
 *
 * Read from the `impl MockPlatform` block only, so trait implementations
 * (`navigate_to`, `confirm_user_action`, …) are excluded: those are the host
 * seam the core calls, not the surface a test drives.
 */
function rustControlSurface(): string[] {
  const source = readFileSync(MOCK_RS, "utf8");
  const start = source.indexOf("impl MockPlatform {");
  expect(start).toBeGreaterThan(-1);
  // The inherent impl ends at the first line that is exactly "}".
  const end = source.indexOf("\n}\n", start);
  expect(end).toBeGreaterThan(start);
  const block = source.slice(start, end);

  return [...block.matchAll(/\n    pub (?:async )?fn ([a-z0-9_]+)/g)]
    .map((match) => match[1])
    .filter((name) => name !== "new" && name !== "with_config");
}

describe("mock host surface agreement", () => {
  it("exposes every Rust MockPlatform control method", () => {
    const host = createMockHost();
    const missing = rustControlSurface()
      .map(jsName)
      // `Object.hasOwn`, not `in`: `in` walks `Object.prototype`, so a Rust
      // `to_string`, `has_own_property` or `value_of` would be reported as
      // present on a host that has no such member at all.
      .filter((name) => !Object.hasOwn(host, name));

    expect(
      missing,
      `createMockHost is missing control methods present on the Rust ` +
        `MockPlatform: ${missing.join(", ")}. Add them, or rename in both.`,
    ).toEqual([]);
  });

  it("has no control method the Rust MockPlatform lacks", () => {
    // The other direction. Walking Rust -> JS alone means a capability dropped
    // from `mock.rs` while `createMockHost` keeps it leaves the two surfaces
    // disagreeing with nothing failing.
    const known = new Set(rustControlSurface().map(jsName));
    const extra = Object.keys(createMockHost()).filter(
      (name) => !known.has(name) && !Object.hasOwn(JS_ONLY, name),
    );

    expect(
      extra,
      `createMockHost has control methods the Rust MockPlatform does not: ` +
        `${extra.join(", ")}. Add them there, or record why they are JS-only ` +
        `in JS_ONLY.`,
    ).toEqual([]);
  });

  it("keeps the alias and JS-only maps live", () => {
    // Both maps are escape hatches from the two checks above, so a stale entry
    // silently widens them. An alias naming a Rust method that no longer
    // exists, or a JS-only entry for a member that is gone, fails here.
    const rust = new Set(rustControlSurface());
    const host = createMockHost();
    expect(Object.keys(ALIASES).filter((name) => !rust.has(name))).toEqual([]);
    expect(
      Object.keys(JS_ONLY).filter((name) => !Object.hasOwn(host, name)),
    ).toEqual([]);
  });

  it("reads a whole Rust surface, so the check cannot pass vacuously", () => {
    // A regex that silently matched nothing, or a block slice that stopped
    // early, would make the checks above green forever. Pin a floor plus the
    // first, a middle and the last method in the block, so a parse truncated
    // anywhere in it is visible.
    const surface = rustControlSurface();
    expect(surface.length).toBeGreaterThan(30);
    expect(surface[0]).toBe("navigations");
    expect(surface).toContain("clear_storage");
    expect(surface.at(-1)).toBe("reset");
  });
});
