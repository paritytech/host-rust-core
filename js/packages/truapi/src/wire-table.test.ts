// Programmatic wire-equality loop.
//
// `wire-equality.test.ts` exercises a handful of hand-picked frames. This file
// iterates every generated (trait, method) frame pair and asserts the codec
// round-trips a sentinel payload and produces the expected byte layout for
// each.

import type { Result } from "neverthrow";
import { describe, expect, it } from "bun:test";

import { str } from "./scale.js";
import { decodeWireMessage, encodeWireMessage } from "./transport.js";
import * as W from "./generated/wire-table.js";

function toHex(u: Uint8Array): string {
    return Array.from(u)
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
}

function expectedWire(
    reqId: string,
    traitId: number,
    methodId: number,
    valueBytes: Uint8Array,
): Uint8Array {
    const idBytes = str.enc(reqId);
    const out = new Uint8Array(idBytes.length + 2 + valueBytes.length);
    out.set(idBytes, 0);
    out[idBytes.length] = traitId;
    out[idBytes.length + 1] = methodId;
    out.set(valueBytes, idBytes.length + 2);
    return out;
}

/** Return the successful result value or fail the test with context. */
function unwrap<T>(result: Result<T, { message: string }>, message: string): T {
    return result.match(
        (value) => value,
        (error): never => {
            throw new Error(`${message}: ${error.message}`);
        },
    );
}

const frames = Object.entries(W as Record<string, Record<string, number>>).flatMap(
    ([method, ids]) => {
        const { trait: traitId, ...kinds } = ids;
        return Object.entries(kinds).map(([kind, id]) => ({ method, kind, traitId, id }));
    },
);

describe("generated wire-table round-trip", () => {
    it("exposes a non-empty set of wire frame constants", () => {
        expect(frames.length).toBeGreaterThan(0);
    });

    it("gives every constant a trait discriminant", () => {
        for (const [method, ids] of Object.entries(W as Record<string, Record<string, number>>)) {
            expect(Number.isInteger(ids.trait), `${method} is missing a trait id`).toBe(true);
        }
    });

    // Per-pair sentinel payload so any cross-talk between pairs surfaces as a
    // concrete byte mismatch rather than a silent equality.
    it.each(frames)("round-trips $method.$kind (pair ($traitId, $id))", ({ traitId, id }) => {
        const sentinel = new Uint8Array([traitId, id, 0xa5, ~id & 0xff, 0x5a]);
        const requestId = `r:${traitId}:${id}`;

        const encoded = unwrap(
            encodeWireMessage({
                requestId,
                payload: { traitId, methodId: id, value: sentinel },
            }),
            "encode",
        );
        expect(toHex(encoded)).toBe(toHex(expectedWire(requestId, traitId, id, sentinel)));

        const decoded = unwrap(decodeWireMessage(encoded), "decode");
        expect(decoded.requestId).toBe(requestId);
        expect(decoded.payload.traitId).toBe(traitId);
        expect(decoded.payload.methodId).toBe(id);
        expect(toHex(decoded.payload.value)).toBe(toHex(sentinel));
    });
});
