import { describe, expect, it } from "bun:test";
import { bool, decodeAll, Struct } from "./scale.js";

describe("decodeAll", () => {
    const response = Struct({ granted: bool });

    it("decodes only the supplied byte view", () => {
        const frame = Uint8Array.of(42, 0, 42);
        expect(decodeAll(response, frame.subarray(1, 2))).toEqual({ granted: false });
    });

    it("rejects an otherwise valid approval with extra payload bytes", () => {
        expect(() => decodeAll(response, Uint8Array.of(1, 0))).toThrow(
            "Unexpected trailing SCALE bytes",
        );
    });

    it("rejects invalid SCALE booleans instead of treating them as approval", () => {
        for (const byte of [2, 255]) {
            expect(() => decodeAll(response, Uint8Array.of(byte))).toThrow("Invalid SCALE boolean");
        }
    });
});
