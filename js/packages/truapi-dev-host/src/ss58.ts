import { blake2b } from "@noble/hashes/blake2.js";
import { hexToBytes, utf8ToBytes } from "@noble/hashes/utils.js";

const BASE58_ALPHABET =
  "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const SS58_PREFIX_CONTEXT = utf8ToBytes("SS58PRE");

function base58Encode(bytes: Uint8Array): string {
  let value = 0n;
  for (const byte of bytes) value = value * 256n + BigInt(byte);
  let encoded = "";
  while (value > 0n) {
    encoded = BASE58_ALPHABET[Number(value % 58n)] + encoded;
    value /= 58n;
  }
  for (const byte of bytes) {
    if (byte !== 0) break;
    encoded = BASE58_ALPHABET[0] + encoded;
  }
  return encoded;
}

/**
 * SS58-encode a 32-byte public key, given as bytes or a 0x-prefixed hex
 * string (the wire client's `HexString`). Only simple one-byte network
 * prefixes (0–63) are supported — enough to print an account for pasting
 * into an explorer, which is all a dev host needs.
 */
export function ss58Encode(key: Uint8Array | string, prefix = 0): string {
  const publicKey =
    typeof key === "string" ? hexToBytes(key.replace(/^0x/, "")) : key;
  if (publicKey.length !== 32) {
    throw new Error(`expected a 32-byte public key, got ${publicKey.length}`);
  }
  if (prefix < 0 || prefix > 63) {
    throw new Error(`unsupported SS58 prefix ${prefix} — only 0-63`);
  }
  const payload = new Uint8Array(1 + publicKey.length);
  payload[0] = prefix;
  payload.set(publicKey, 1);

  const checksummed = new Uint8Array(
    SS58_PREFIX_CONTEXT.length + payload.length,
  );
  checksummed.set(SS58_PREFIX_CONTEXT, 0);
  checksummed.set(payload, SS58_PREFIX_CONTEXT.length);
  const checksum = blake2b(checksummed, { dkLen: 64 }).slice(0, 2);

  const full = new Uint8Array(payload.length + 2);
  full.set(payload, 0);
  full.set(checksum, payload.length);
  return base58Encode(full);
}
