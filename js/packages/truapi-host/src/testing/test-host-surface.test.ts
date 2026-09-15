import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/**
 * Every member of `@parity/host-api-test-sdk`'s `TestHostAPI`, as shipped.
 *
 * Pinned rather than imported: this package does not depend on that one, and
 * should not gain a dependency on it to check a compatibility claim. Refresh
 * from `TestHostAPI` in its `src/types.ts` on `origin/main` -- not from a local
 * checkout, which has repeatedly been behind what is published.
 *
 * Read from the shipped 0.12.1.
 */
const TEST_HOST_API = [
  "clearChatState",
  "clearNavigationLog",
  "clearNotificationLog",
  "clearPaymentLog",
  "clearPermissionLog",
  "clearPreimages",
  "clearSigningLog",
  "clearStatements",
  "dispose",
  "getChainStatus",
  "getChatBots",
  "getChatMessageLog",
  "getChatRooms",
  "getConnectionStatus",
  "getGrantedPermissions",
  "getIsAuthenticated",
  "getNavigationLog",
  "getNotificationLog",
  "getPaymentLog",
  "getPermissionLog",
  "getPreimages",
  "getSigningLog",
  "getSubmittedStatements",
  "getTheme",
  "grantPermission",
  "injectChatAction",
  "injectStatement",
  "revokePermission",
  "seedPreimage",
  "setAccounts",
  "setEnforcePermissions",
  "setLoginBehavior",
  "setPaymentBalance",
  "setPaymentTopUpBehavior",
  "setPermissionBehavior",
  "setTheme",
  "simulateDisconnect",
  "simulatePaymentStatus",
  "simulateReconnect",
  "switchAccount",
] as const;

/** Member names declared on the `TestHost` interface. */
function fixtureMembers(): string[] {
  const source = readFileSync(
    fileURLToPath(new URL("./playwright.ts", import.meta.url)),
    "utf8",
  );
  const start = source.indexOf("export interface TestHost ");
  expect(start).toBeGreaterThan(-1);
  // The interface ends at the first line that is a closing brace on its own.
  const body = source.slice(start).split("\n}")[0];
  return [...body.matchAll(/^ {2}([A-Za-z_][A-Za-z0-9_]*)\??[(<]/gm)].map(
    (match) => match[1],
  );
}

describe("TestHost covers TestHostAPI", () => {
  it("declares every member a migrating suite can call", () => {
    const ours = new Set(fixtureMembers());
    const missing = TEST_HOST_API.filter((name) => !ours.has(name));
    // Named, so a failure says which call a migrating suite would lose rather
    // than only that the counts differ.
    expect(missing).toEqual([]);
  });

  it("actually parsed the interface", () => {
    // Without this, a regex that matched nothing would make the check above
    // vacuously green -- `missing` would be every name, but a regex matching
    // nothing is far likelier to be silently wrong than the surface is.
    const ours = fixtureMembers();
    expect(ours.length).toBeGreaterThanOrEqual(TEST_HOST_API.length);
    expect(ours).toContain("productFrame");
  });
});
