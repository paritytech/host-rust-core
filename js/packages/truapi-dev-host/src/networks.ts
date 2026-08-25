/**
 * One network knob steers both sides of a local dev-host setup: the CLI gets
 * `--network <cliName>`, the app gets the matching genesis hash, and bare
 * product labels resolve into the network's own product namespace. Keeping
 * them behind a single preset means they cannot disagree.
 */
export interface NetworkPreset {
  /** CLI-native `--network` preset name. */
  cliName: string;
  /** Genesis hash of the network's hub chain, for the app side. */
  genesisHash: string;
  /**
   * Product-namespace TLD a bare label resolves under on this network.
   * A host only signs for the product id it serves, so the suffix must be
   * selected by network — never hardcoded, never appended to an already
   * qualified id.
   */
  productTld: string;
}

export const NETWORK_PRESETS: Record<string, NetworkPreset> = {
  "paseo-next-v2": {
    cliName: "paseo-next-v2",
    genesisHash:
      "0x23e730eb1c6fecae09c917439a5038cb6122d0d48980e8b9bbf0ff56f94a2ca6",
    productTld: "paseo",
  },
  previewnet: {
    cliName: "previewnet",
    genesisHash:
      "0x4d11c803cc6921429e3876638977ad006ea1bba8cd3976a0bca2f164e7026210",
    // The CLI validates DotNS identifiers as `.dot` or `localhost` today, so
    // this stays the honest mapping until it learns Previewnet's `.test`.
    productTld: "dot",
  },
};

/** Friendly aliases for the CLI-native preset names. */
export const NETWORK_ALIASES: Record<string, string> = {
  nextv2: "paseo-next-v2",
  preview: "previewnet",
};

export interface ResolvedNetwork extends NetworkPreset {
  /** The CLI-native preset name the input resolved to. */
  name: string;
}

/**
 * Resolve a network name or alias to its preset. Throws on unknown names so a
 * typo cannot silently start a host against the wrong network.
 */
export function resolveNetwork(input?: string): ResolvedNetwork {
  const name = NETWORK_ALIASES[input ?? "nextv2"] ?? input ?? "nextv2";
  const preset = NETWORK_PRESETS[name];
  if (!preset) {
    const known = [
      ...Object.keys(NETWORK_ALIASES),
      ...Object.keys(NETWORK_PRESETS),
    ].join(", ");
    throw new Error(`unknown TrUAPI network "${input}" — use one of: ${known}`);
  }
  return { name, ...preset };
}

/**
 * Resolve the product id the host will serve and the app will act as.
 *
 * A bare label selects the network's own product namespace; an explicitly
 * qualified id (or a `localhost:<port>` id) is respected verbatim. With no
 * override the fallback applies — typically `localhost:<app port>`, which is
 * what an app derives for itself in local dev.
 */
export function resolveProductId(
  override: string | undefined,
  network: NetworkPreset,
  fallback: string,
): string {
  if (!override) return fallback;
  if (override.includes(".") || override.includes(":")) return override;
  return `${override}.${network.productTld}`;
}
