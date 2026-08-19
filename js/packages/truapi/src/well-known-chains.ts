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
    "0x89a63b11fef2c0273fc72c0d864da0793a665dade5db153e0cab995348c5440f",
} as const satisfies WellKnownChain;

export const PREVIEWNET_ASSET_HUB = {
  name: "Previewnet Hub",
  network: "Testnet",
  genesis:
    "0x4d11c803cc6921429e3876638977ad006ea1bba8cd3976a0bca2f164e7026210",
} as const satisfies WellKnownChain;

export const PREVIEWNET_INDIVIDUALITY = {
  name: "Previewnet Individuality",
  network: "Testnet",
  genesis:
    "0x3138c6d4ce58c760047a413c2a930e919b4673a841ab4890de59aac3bd037f3d",
} as const satisfies WellKnownChain;
