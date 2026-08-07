// Wire byte-equality smoke test.
//
// `encodeWireMessage` must produce the same bytes as the Rust `ProtocolMessage`
// encoder for the canonical reference vectors. The Rust side pins these in
// `crates/truapi-server/src/frame.rs` (`mod tests`); we compute them here
// independently and compare.

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

function expectedWire(traitId: number, methodId: number, valueBytes: Uint8Array): Uint8Array {
    const reqId = str.enc("p:1");
    const out = new Uint8Array(reqId.length + 2 + valueBytes.length);
    out.set(reqId, 0);
    out[reqId.length] = traitId;
    out[reqId.length + 1] = methodId;
    out.set(valueBytes, reqId.length + 2);
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

describe("encodeWireMessage / decodeWireMessage wire equality", () => {
    it("pins the handshake frame end-to-end: requestId + 0xc0 0x00 + payload", () => {
        // Trait 192 = system, method 0 = handshake request. This locks the
        // system trait to the first id above the codec 1 flat-method range:
        // the handshake is the first frame either side sends, so its envelope
        // must never drift, and a codec 1 peer's frame must never reach it.
        expect(W.SYSTEM_HANDSHAKE.trait).toBe(192);
        expect(W.SYSTEM_HANDSHAKE.request).toBe(0);

        const inner = new Uint8Array([0x00, 0x02]); // V1 variant + codec_version=2
        const encoded = unwrap(
            encodeWireMessage({
                requestId: "p:1",
                payload: {
                    traitId: W.SYSTEM_HANDSHAKE.trait,
                    methodId: W.SYSTEM_HANDSHAKE.request,
                    value: inner,
                },
            }),
            "encode handshake_request",
        );
        // [0c 70 3a 31] "p:1" + [c0] system trait + [00] handshake request + payload.
        expect(toHex(encoded)).toBe("0c703a31c0000002");
        expect(toHex(encoded)).toBe(toHex(expectedWire(192, 0, inner)));

        const decoded = unwrap(decodeWireMessage(encoded), "decode handshake_request");
        expect(decoded.payload.traitId).toBe(192);
        expect(decoded.payload.methodId).toBe(0);
        expect(toHex(decoded.payload.value)).toBe(toHex(inner));
    });

    it("encodes account_get_request (pair (193, 4)) to match the golden fixture", () => {
        // payload = V1(("foo", 0u32)); same vector as the Rust golden fixture.
        const inner = new Uint8Array([
            0x00, // V1 variant
            ...str.enc("foo"), // compact-len + utf8
            0x00,
            0x00,
            0x00,
            0x00, // u32 = 0 LE
        ]);
        const encoded = unwrap(
            encodeWireMessage({
                requestId: "p:1",
                payload: {
                    traitId: W.ACCOUNT_GET_ACCOUNT.trait,
                    methodId: W.ACCOUNT_GET_ACCOUNT.request,
                    value: inner,
                },
            }),
            "encode account_get_request",
        );
        expect(toHex(encoded)).toBe(toHex(expectedWire(193, 4, inner)));
        expect(toHex(encoded)).toBe("0c703a31c104000c666f6f00000000");
    });

    it("round-trips a local_storage_read frame through encode + decode", () => {
        const inner = new Uint8Array([0x00, 0x42, 0xab, 0xcd]);
        const encoded = unwrap(
            encodeWireMessage({
                requestId: "p:1",
                payload: {
                    traitId: W.LOCAL_STORAGE_READ.trait,
                    methodId: W.LOCAL_STORAGE_READ.request,
                    value: inner,
                },
            }),
            "encode local_storage_read_request",
        );
        const decoded = unwrap(decodeWireMessage(encoded), "decode local_storage_read_request");
        expect(decoded.requestId).toBe("p:1");
        expect(decoded.payload.traitId).toBe(W.LOCAL_STORAGE_READ.trait);
        expect(decoded.payload.methodId).toBe(W.LOCAL_STORAGE_READ.request);
        expect(toHex(decoded.payload.value)).toBe(toHex(inner));
    });

    it("rejects an invalid outbound trait discriminant", () => {
        const result = encodeWireMessage({
            requestId: "p:1",
            payload: { traitId: 256, methodId: 0, value: new Uint8Array() },
        });
        expect(result.isErr()).toBe(true);
        expect(result._unsafeUnwrapErr().message).toMatch(/Invalid wire trait discriminant/);
    });

    it("rejects an invalid outbound method discriminant", () => {
        const result = encodeWireMessage({
            requestId: "p:1",
            payload: { traitId: 0, methodId: 256, value: new Uint8Array() },
        });
        expect(result.isErr()).toBe(true);
        expect(result._unsafeUnwrapErr().message).toMatch(/Invalid wire method discriminant/);
    });

    it("rejects a truncated frame with no trait byte", () => {
        const truncated = str.enc("p:1"); // just the requestId, nothing after.
        const result = decodeWireMessage(truncated);
        expect(result.isErr()).toBe(true);
        expect(result._unsafeUnwrapErr().message).toMatch(/missing trait discriminant byte/);
    });

    it("rejects a truncated frame with a trait byte but no method byte", () => {
        const reqId = str.enc("p:1");
        const truncated = new Uint8Array(reqId.length + 1);
        truncated.set(reqId, 0);
        truncated[reqId.length] = 0x00;
        const result = decodeWireMessage(truncated);
        expect(result.isErr()).toBe(true);
        expect(result._unsafeUnwrapErr().message).toMatch(/missing method discriminant byte/);
    });

    it("round-trips a 32 KiB requestId via the mode-2 compact-len prefix", () => {
        // Mirrors Rust `max_length_request_id_mode_two_round_trips` so both sides
        // agree the high-shift branch in scanStrEnd is correct.
        const longId = "y".repeat(32 * 1024);
        const inner = new Uint8Array([0x00, 0xab, 0xcd]);
        const encoded = unwrap(
            encodeWireMessage({
                requestId: longId,
                payload: {
                    traitId: W.ACCOUNT_GET_ACCOUNT.trait,
                    methodId: W.ACCOUNT_GET_ACCOUNT.request,
                    value: inner,
                },
            }),
            "encode long-id account_get_request",
        );
        // Confirm a mode-2 prefix was actually emitted; otherwise the test would
        // silently exercise mode-0/1 and the assertion would be hollow.
        expect(encoded[0] & 0b11).toBe(0b10);
        const decoded = unwrap(decodeWireMessage(encoded), "decode long-id account_get_request");
        expect(decoded.requestId).toBe(longId);
        expect(decoded.payload.traitId).toBe(W.ACCOUNT_GET_ACCOUNT.trait);
        expect(decoded.payload.methodId).toBe(W.ACCOUNT_GET_ACCOUNT.request);
        expect(toHex(decoded.payload.value)).toBe(toHex(inner));
    });
});
