import { accessSync, constants, existsSync, realpathSync } from "node:fs";
import { createRequire } from "node:module";
import { delimiter, dirname, join, parse, sep } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Where a `truapi-host` binary came from, in resolution order: an explicit
 * option, the `TRUAPI_HOST_BIN` environment variable, an installed platform
 * package, a local repository build, or plain `PATH` lookup.
 */
export type BinarySource =
  | "explicit"
  | "env"
  | "platform-package"
  | "checkout"
  | "path";

export interface ResolvedBinary {
  /** Command to spawn: an absolute path, or a bare name for PATH lookup. */
  command: string;
  source: BinarySource;
}

const EXE = process.platform === "win32" ? "truapi-host.exe" : "truapi-host";

export const INSTALL_HELP = [
  "No `truapi-host` binary found. Either:",
  "",
  "  - wait for the @parity/truapi-dev-host platform packages (they install",
  "    a matching binary automatically), or",
  "  - install it with cargo, straight from the repo:",
  "",
  "        cargo install --git https://github.com/paritytech/host-rust-core \\",
  "          --bin truapi-host --locked truapi-host-cli",
  "",
  "    (it lands in Cargo's bin dir, so ~/.cargo/bin must be on PATH), or",
  "  - point TRUAPI_HOST_BIN at a locally built binary",
  "    (cargo build -p truapi-host-cli in a repo checkout).",
  "",
  "Note: `npm i @parity/truapi-host` is a different package — the WASM host",
  "runtime, not this CLI.",
].join("\n");

const require = createRequire(import.meta.url);

/** The version-pinned binary an installed platform package provides. */
function platformPackageBinary(): string | undefined {
  const pkg = `@parity/truapi-dev-host-${process.platform}-${process.arch}`;
  try {
    return require.resolve(`${pkg}/${EXE}`);
  } catch {
    return undefined;
  }
}

/**
 * A cargo-built binary in a host-rust-core checkout. This package sits in
 * `js/packages/` of that repo, so when consumed from a checkout (workspace
 * link or portal install) walking up from the package's real location finds
 * the repo root and its `target/` build.
 */
function checkoutBinary(): string | undefined {
  let dir = dirname(realpathSync(fileURLToPath(import.meta.url)));
  const { root } = parse(dir);
  while (dir !== root) {
    if (existsSync(join(dir, "rust", "crates", "truapi-host-cli"))) {
      for (const profile of ["release", "debug"]) {
        const bin = join(dir, "target", profile, EXE);
        if (existsSync(bin)) return bin;
      }
      return undefined;
    }
    dir = dirname(dir);
  }
  return undefined;
}

/**
 * A `truapi-host` on PATH — skipping every `node_modules/.bin` entry. This
 * package's own bin is *named* `truapi-host`, and package runners (yarn, npm,
 * pnpm) prepend `node_modules/.bin` to PATH, so a naive `spawn("truapi-host")`
 * from inside a `yarn dev` script resolves straight back to the shim and
 * recurses forever. Only a real binary outside a bin dir counts.
 */
function pathBinary(): string | undefined {
  const entries = (process.env.PATH ?? "").split(delimiter);
  for (const entry of entries) {
    if (!entry || entry.split(sep).includes(".bin")) continue;
    const candidate = join(entry, EXE);
    try {
      accessSync(candidate, constants.X_OK);
      return candidate;
    } catch {
      // not here — keep walking PATH
    }
  }
  return undefined;
}

/**
 * Resolve the `truapi-host` binary to run, always to a concrete path.
 *
 * Order: explicit option, `TRUAPI_HOST_BIN`, installed platform package,
 * checkout build, PATH lookup. The lockfile-pinned platform package outranks
 * anything unpinned; explicit overrides outrank everything, so host
 * developers can point at a work-in-progress build. Throws with install
 * guidance when no rung yields a binary.
 */
export function resolveHostBinary(explicit?: string): ResolvedBinary {
  if (explicit) return { command: explicit, source: "explicit" };
  const env = process.env.TRUAPI_HOST_BIN;
  if (env) return { command: env, source: "env" };
  const platform = platformPackageBinary();
  if (platform) return { command: platform, source: "platform-package" };
  const checkout = checkoutBinary();
  if (checkout) return { command: checkout, source: "checkout" };
  const onPath = pathBinary();
  if (onPath) return { command: onPath, source: "path" };
  throw new Error(INSTALL_HELP);
}
