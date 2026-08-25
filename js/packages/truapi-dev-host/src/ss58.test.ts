import { describe, expect, test } from "bun:test";
import { ss58Encode } from "./ss58.js";

const hex = (value: string): Uint8Array =>
  new Uint8Array(
    value.match(/../g)?.map((byte) => Number.parseInt(byte, 16)) ?? [],
  );

// The well-known dev account `//Alice`.
const ALICE =
  "d43593c715fdd31c61141abd04a99fd6822c8558854ccde39a5684e7a56da27d";

describe("ss58Encode", () => {
  test("encodes with the Polkadot prefix by default", () => {
    expect(ss58Encode(hex(ALICE))).toBe(
      "15oF4uVJwmo4TdGW7VfQxNLavjCXviqxT9S1MgbjMNHr6Sp5",
    );
  });

  test("encodes with the generic Substrate prefix", () => {
    expect(ss58Encode(hex(ALICE), 42)).toBe(
      "5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY",
    );
  });

  test("rejects non-32-byte keys", () => {
    expect(() => ss58Encode(hex("00"))).toThrow(/32-byte/);
  });
});
