// Named dev accounts for the test host.
//
// A TrUAPI signing host establishes a session from raw BIP-39 entropy, so a
// "dev account" here is just a fixed 32-byte value. The bytes below are
// arbitrary but stable, which is what makes a test's addresses reproducible
// across runs and machines.
//
// THESE ARE NOT POLKADOT-JS DEV ACCOUNTS. `//Alice` and friends are derived
// from a seed phrase through sr25519 soft/hard junctions; TrUAPI derives a root
// keypair from entropy and then a per-product subtree from that. The names are
// borrowed for familiarity, the addresses are not the same, and anything that
// asserts a literal `5Grw...` address from polkadot-js will not match. Fund or
// pin addresses by reading them back from the host, never by hard-coding a
// well-known one.

/** Name of a built-in dev account. */
export type DevAccountName = "alice" | "bob" | "charlie" | "dave";

/** A dev account: a name and the entropy its session is activated from. */
export interface DevAccount {
  /** The name a test refers to it by. */
  name: string;
  /** 32 bytes of BIP-39 entropy. */
  entropy: Uint8Array;
}

/** Fill 32 bytes with a marker, so each account is visibly distinct in a dump. */
function entropyFor(marker: number): Uint8Array {
  return new Uint8Array(32).fill(marker);
}

/**
 * The built-in dev accounts.
 *
 * Distinct markers rather than sequential values: a one-byte difference is easy
 * to miss when comparing two hex dumps in a failing test.
 */
export const DEV_ACCOUNTS: Record<DevAccountName, Uint8Array> = {
  alice: entropyFor(0xa1),
  bob: entropyFor(0xb2),
  charlie: entropyFor(0xc3),
  dave: entropyFor(0xd4),
};

/** Whether `name` is one of the built-in dev accounts. */
export function isDevAccountName(name: string): name is DevAccountName {
  return name in DEV_ACCOUNTS;
}

/**
 * Resolve an account spec to the entropy its session activates from.
 *
 * Accepts a built-in name or an explicit `{ name, entropy }`, so a suite that
 * needs a specific key is not forced to use one of the four.
 */
export function resolveAccount(spec: DevAccountName | DevAccount): DevAccount {
  if (typeof spec !== "string") {
    if (spec.entropy.length !== 32) {
      throw new Error(
        `dev account ${spec.name} needs 32 bytes of entropy, got ${spec.entropy.length}`,
      );
    }
    return spec;
  }
  const entropy = DEV_ACCOUNTS[spec];
  if (!entropy) {
    throw new Error(
      `unknown dev account "${spec}"; known: ${Object.keys(DEV_ACCOUNTS).join(", ")}`,
    );
  }
  return { name: spec, entropy };
}

/**
 * Real public networks a suite can proxy to.
 *
 * Genesis hashes are the chains' own, not {@link MOCK_GENESIS} placeholders:
 * the core asks for a chain by hash, so proxying only works when the hash the
 * runtime config carries is the real one.
 *
 * Using these makes a run non-hermetic. It inherits whatever the public chain
 * is doing -- accumulated state from other runs, contracts that were reaped,
 * endpoint outages -- which is the cost of testing against real inclusion.
 */
export const LIVE_CHAINS = {
  /**
   * Paseo Asset Hub. No genesis hash on purpose: this chain has been reset
   * more than once, every pinned copy of its hash has gone stale, and an
   * unhashed proxy takes every request instead of routing on a value that
   * rots.
   */
  paseoAssetHub: { rpcUrl: "wss://paseo-asset-hub-next-rpc.polkadot.io" },
} as const;
