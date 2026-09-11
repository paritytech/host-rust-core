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
    "0x4349b00e54897e21196fd331015fc5be0f14e118beb0375ed2bb1793737bb57a",
} as const satisfies WellKnownChain;

export const PASEO_NEXT_V2_INDIVIDUALITY = {
  name: "Paseo Next v2 Individuality",
  network: "Testnet",
  genesis:
    "0x4a2b5b737de1da59e209b0000a876ec2fa20035dc34fd292a848da32d255ad48",
} as const satisfies WellKnownChain;

export const PREVIEWNET_ASSET_HUB = {
  name: "Previewnet Hub",
  network: "Testnet",
  genesis:
    "0xc27c8bf3f13f96dc2130cd2b0a3debe57618fd02521ecc1902bd7dd4ed83d2fe",
} as const satisfies WellKnownChain;

export const PREVIEWNET_INDIVIDUALITY = {
  name: "Previewnet Individuality",
  network: "Testnet",
  genesis:
    "0xf720c28fe3315e67fa799a616fc59abad47dd257b1a336af6538435844d35218",
} as const satisfies WellKnownChain;
