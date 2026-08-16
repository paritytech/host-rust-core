/** Well-known chain descriptors. Each chain is its own `export const` so that
 * bundlers can tree-shake the ones a consumer does not import. */

import type { HexString } from "./scale.js";

export interface WellKnownChain {
  readonly name: string;
  readonly network: "Mainnet" | "Testnet";
  readonly genesis: HexString;
}

export const PASEO_NEXT_V2_ASSET_HUB = {
  name: "Paseo Next v2 Hub",
  network: "Testnet",
  genesis:
    "0x23e730eb1c6fecae09c917439a5038cb6122d0d48980e8b9bbf0ff56f94a2ca6",
} as const satisfies WellKnownChain;

export const PASEO_NEXT_V2_INDIVIDUALITY = {
  name: "Paseo Next v2 Individuality",
  network: "Testnet",
  genesis:
    "0xc5af1826b31493f08b7e2a823842f98575b806a784126f28da9608c68665afa5",
} as const satisfies WellKnownChain;
