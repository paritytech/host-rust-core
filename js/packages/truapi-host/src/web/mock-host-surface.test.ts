// The JS mock host and the Rust `MockPlatform` are siblings: both implement the
// same host seam, one for browser tests against the WASM core and one for Rust
// tests against the native core. A capability added to one and forgotten on the
// other is exactly the drift this mock exists to remove, and it is invisible to
// `tsc` because the two surfaces share no types.
//
// So the agreement is asserted here, against the Rust source. Adding a control
// method to `mock.rs` without adding it to `createMockHost` fails this test.
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

  return [...block.matchAll(/\n    pub fn ([a-z0-9_]+)/g)]
    .map((match) => match[1])
    .filter((name) => name !== "new" && name !== "with_config");
}

describe("mock host surface agreement", () => {
  it("exposes every Rust MockPlatform control method", () => {
    const host = createMockHost();
    const missing = rustControlSurface()
      .map(jsName)
      .filter((name) => !(name in host));

    expect(
      missing,
      `createMockHost is missing control methods present on the Rust ` +
        `MockPlatform: ${missing.join(", ")}. Add them, or rename in both.`,
    ).toEqual([]);
  });

  it("reads a non-empty Rust surface, so the check cannot pass vacuously", () => {
    // A regex that silently matched nothing would make the test above green
    // forever. Pin a floor and a few known members.
    const surface = rustControlSurface();
    expect(surface.length).toBeGreaterThan(20);
    expect(surface).toContain("reviews");
    expect(surface).toContain("grant_permission");
    expect(surface).toContain("reset");
  });
});
