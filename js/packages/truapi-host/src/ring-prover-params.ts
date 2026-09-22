/**
 * Ring-VRF prover parameters, served to the core from the assets published
 * beside the WASM bundle.
 *
 * The core carries none: the largest domain's parameters are several MiB of
 * incompressible data for a capability most sessions never reach. Nothing here
 * runs until a product asks for a local ring-VRF proof and this host holds a
 * key for it, so a session that never proves issues no request at all.
 */

/** Manifest keys, in the SCALE tag order of the core's `RingProverDomain`. */
const DOMAIN_KEYS = ["domain11", "domain12", "domain16"] as const;

/** One published parameter file. */
export interface RingProverParamsEntry {
  /** File name beside the WASM bundle, carrying a prefix of its hash. */
  file: string;
  /** Blake2b-256 of the file, which the core checks before installing. */
  blake2b256: string;
  /** Length in bytes. */
  bytes: number;
}

/** `srs-manifest.json`, keyed by ring domain. */
export type RingProverParamsManifest = Partial<
  Record<(typeof DOMAIN_KEYS)[number], RingProverParamsEntry>
>;

/** Where the loader reads from, so it is testable without a network. */
export interface RingProverParamsDeps {
  /** Read the published manifest. Called at most once per worker. */
  loadManifest: () => Promise<RingProverParamsManifest>;
  /** Read one published file by name. */
  fetchBytes: (file: string) => Promise<Uint8Array | undefined>;
}

/**
 * Build the `loadRingProverParams` host callback.
 *
 * Each domain is fetched at most once per worker; the browser cache carries it
 * across reloads, and the files are named by content so a cached one can never
 * be stale. A domain the manifest does not carry resolves to `undefined`,
 * which the core reads as "this host serves no parameters" and answers by
 * reaching the paired signer.
 */
export function createRingProverParamsLoader(
  deps: RingProverParamsDeps,
): (domain: Uint8Array) => Promise<Uint8Array | undefined> {
  const inFlight = new Map<string, Promise<Uint8Array | undefined>>();
  let manifest: Promise<RingProverParamsManifest> | undefined;

  return (domain) => {
    const key = DOMAIN_KEYS[domain[0] ?? -1];
    if (!key) return Promise.resolve(undefined);

    const cached = inFlight.get(key);
    if (cached) return cached;

    manifest ??= deps.loadManifest();
    const pending = manifest
      .then((entries) => {
        const entry = entries[key];
        return entry ? deps.fetchBytes(entry.file) : undefined;
      })
      .catch((err: unknown) => {
        // A failed read is not a verdict about this host: let the next proof
        // try again rather than answering "no parameters" for the session.
        inFlight.delete(key);
        manifest = undefined;
        throw err;
      });
    inFlight.set(key, pending);
    return pending;
  };
}
