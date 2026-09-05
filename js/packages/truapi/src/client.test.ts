import type { Result } from "neverthrow";
import { describe, expect, it } from "bun:test";

import { createTransport } from "./client.js";
import * as S from "./scale.js";
import { str, type CallErrorValue } from "./scale.js";
import { createClient, SubscriptionError } from "./generated/client.js";
import * as T from "./generated/types.js";
import * as W from "./generated/wire-table.js";
import {
  encodeWireMessage,
  MESSAGE_TYPE_INTERRUPT,
  MESSAGE_TYPE_RECEIVE,
  MESSAGE_TYPE_REQUEST,
  MESSAGE_TYPE_RESPONSE,
  MESSAGE_TYPE_START,
  MESSAGE_TYPE_STOP,
  PROTOCOL_ERROR_METHOD_ID,
  PROTOCOL_ERROR_TRAIT_ID,
  UnsupportedMessageError,
} from "./transport.js";

function toHex(u: Uint8Array): string {
    return Array.from(u)
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
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

/** Create an in-memory provider plus helpers for injecting frames and closes. */
function providerFixture() {
    const sent: Uint8Array[] = [];
    let listener: (message: Uint8Array) => void = () => {};
    let closeListener: (error: Error) => void = () => {};
    return {
        sent,
        provider: {
            postMessage(message: Uint8Array) {
                sent.push(message);
            },
            subscribe(callback: (message: Uint8Array) => void) {
                listener = callback;
                return () => {};
            },
            subscribeClose(callback: (error: Error) => void) {
                closeListener = callback;
                return () => {};
            },
            dispose() {},
        },
        receive(message: Uint8Array) {
            listener(message);
        },
        close(error: Error) {
            closeListener(error);
        },
    };
}

/** Codec for `system_handshake`'s `Response`-leg payload. */
const HANDSHAKE_RESPONSE_CODEC = S.Result(
    T.VersionedHostHandshakeResponse,
    S.CallError(T.VersionedHostHandshakeError),
);

/** Encode a successful V1 host-handshake `Response`-leg payload. */
function handshakeResponsePayload(_value: { success: true; value: undefined }): Uint8Array {
    return HANDSHAKE_RESPONSE_CODEC.enc({ success: true, value: { tag: "V1" } });
}

/**
 * Encode a V1 `account_get_account` `Response`-leg payload. Both legs already
 * carry their own version tag (their own wrapper), so the wrapped shapes
 * passed in are exactly what the wire holds — no further translation.
 */
function accountGetResponsePayload(
    value:
        | {
              success: true;
              value: T.HostAccountGetResponse;
          }
        | {
              success: false;
              value: { tag: "Domain"; value: T.VersionedHostAccountGetError };
          },
): Uint8Array {
    return S.Result(
        T.VersionedHostAccountGetResponse,
        S.CallError(T.VersionedHostAccountGetError),
    ).enc(
        value.success
            ? { success: true, value: { tag: "V1", value: value.value } }
            : value,
    );
}

function rendererStart(
    requestId: string,
    request: T.ProductChatCustomMessageRenderRequest,
): Uint8Array {
    return unwrap(
        encodeWireMessage({
            requestId,
            payload: {
                traitId: W.CHAT_CUSTOM_MESSAGE_RENDER.trait,
                methodId: W.CHAT_CUSTOM_MESSAGE_RENDER.method,
                messageType: MESSAGE_TYPE_START,
                value: T.VersionedProductChatCustomMessageRenderRequest.enc({
                    tag: "V1",
                    value: request,
                }),
            },
        }),
        "encode renderer start",
    );
}

function rendererReceive(requestId: string, node: T.CustomRendererNode): Uint8Array {
    return unwrap(
        encodeWireMessage({
            requestId,
            payload: {
                traitId: W.CHAT_CUSTOM_MESSAGE_RENDER.trait,
                methodId: W.CHAT_CUSTOM_MESSAGE_RENDER.method,
                messageType: MESSAGE_TYPE_RECEIVE,
                value: T.VersionedProductChatCustomMessageRenderItem.enc({
                    tag: "V1",
                    value: node,
                }),
            },
        }),
        "encode renderer receive",
    );
}

/**
 * The fixed frame `transport.ts` sends to decline a host-initiated render:
 * `Some(CallError::HostFailure{reason: "unavailable"})`, with `messageType =
 * Interrupt`. `HostFailure`'s payload doesn't depend on the method's own
 * domain error type, so one constant frame covers every method.
 */
function rendererInterrupt(requestId: string): Uint8Array {
    return unwrap(
        encodeWireMessage({
            requestId,
            payload: {
                traitId: W.CHAT_CUSTOM_MESSAGE_RENDER.trait,
                methodId: W.CHAT_CUSTOM_MESSAGE_RENDER.method,
                messageType: MESSAGE_TYPE_INTERRUPT,
                value: new Uint8Array([
                    1, 4, 44, 117, 110, 97, 118, 97, 105, 108, 97, 98, 108, 101,
                ]),
            },
        }),
        "encode renderer interrupt",
    );
}

function rendererStop(requestId: string): Uint8Array {
    return unwrap(
        encodeWireMessage({
            requestId,
            payload: {
                traitId: W.CHAT_CUSTOM_MESSAGE_RENDER.trait,
                methodId: W.CHAT_CUSTOM_MESSAGE_RENDER.method,
                messageType: MESSAGE_TYPE_STOP,
                value: new Uint8Array(),
            },
        }),
        "encode renderer stop",
    );
}

function protocolError(requestId: string, payload: Uint8Array): Uint8Array {
    return unwrap(
        encodeWireMessage({
            requestId,
            payload: {
                traitId: PROTOCOL_ERROR_TRAIT_ID,
                methodId: PROTOCOL_ERROR_METHOD_ID,
                messageType: MESSAGE_TYPE_RESPONSE,
                value: payload,
            },
        }),
        "encode protocol error",
    );
}

function unsupportedMessage(
    requestId: string,
    traitId: number,
    methodId: number,
): Uint8Array {
    // [0] version index, [0] variant index, then the unsupported pair.
    return protocolError(requestId, new Uint8Array([0, 0, traitId, methodId]));
}

describe("generated client transport", () => {
    it("encodes unit-only enums as a single-byte SCALE discriminant", () => {
        // Unit-only enums expose a string union on the public API while
        // preserving the same single-byte SCALE discriminant encoding.
        expect(toHex(T.HostDevicePermissionRequest.enc("Camera"))).toBe("01");
        expect(T.HostDevicePermissionRequest.dec(new Uint8Array([1]))).toBe("Camera");
    });

    it("wraps generated method requests in the selected wire wrapper", () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);

        const request = {
            productAccountId: {
                dotNsIdentifier: "foo",
                derivationIndex: { tag: "Index", value: 0 },
            },
        };
        void client.account.getAccount(request);

        const expectedPayload = T.VersionedHostAccountGetRequest.enc({
            tag: "V1",
            value: request,
        });
        const expectedFrame = new Uint8Array(str.enc("p:1").length + 3 + expectedPayload.length);
        expectedFrame.set(str.enc("p:1"), 0);
        expectedFrame[str.enc("p:1").length] = 2; // account trait
        expectedFrame[str.enc("p:1").length + 1] = 1; // get_account
        expectedFrame[str.enc("p:1").length + 2] = MESSAGE_TYPE_REQUEST;
        expectedFrame.set(expectedPayload, str.enc("p:1").length + 3);

        expect(toHex(fixture.sent[0])).toBe(toHex(expectedFrame));
    });

    it("uses the transport codec version for generated handshake calls", () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);

        void client.system.handshake();

        const expectedPayload = T.VersionedHostHandshakeRequest.enc({
            tag: "V1",
            value: { codecVersion: 2 },
        });
        const expectedFrame = new Uint8Array(str.enc("p:1").length + 3 + expectedPayload.length);
        expectedFrame.set(str.enc("p:1"), 0);
        expectedFrame[str.enc("p:1").length] = 1; // system trait
        expectedFrame[str.enc("p:1").length + 1] = 0; // handshake
        expectedFrame[str.enc("p:1").length + 2] = MESSAGE_TYPE_REQUEST;
        expectedFrame.set(expectedPayload, str.enc("p:1").length + 3);

        expect(toHex(fixture.sent[0])).toBe(toHex(expectedFrame));
    });

    it("resolves a request from its versioned response envelope", async () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);

        const response = client.system.handshake();
        const frame = unwrap(
            encodeWireMessage({
                requestId: "p:1",
                payload: {
                    traitId: W.SYSTEM_HANDSHAKE.trait,
                    methodId: W.SYSTEM_HANDSHAKE.method,
                    messageType: MESSAGE_TYPE_RESPONSE,
                    value: handshakeResponsePayload({ success: true, value: undefined }),
                },
            }),
            "encode handshake_response",
        );
        fixture.receive(frame);

        const result = await response;
        expect(result.isOk()).toBe(true);
    });

    it("returns the current product context without request arguments", async () => {
        const fixture = providerFixture();
        const client = createClient(createTransport(fixture.provider));

        const response = client.system.getProductContext();
        const frame = unwrap(
            encodeWireMessage({
                requestId: "p:1",
                payload: {
                    traitId: W.SYSTEM_GET_PRODUCT_CONTEXT.trait,
                    methodId: W.SYSTEM_GET_PRODUCT_CONTEXT.method,
                    messageType: MESSAGE_TYPE_RESPONSE,
                    value: S.Result(
                        T.VersionedHostGetProductContextResponse,
                        S.CallError(T.VersionedHostGetProductContextError),
                    ).enc({
                        success: true,
                        value: {
                            tag: "V1",
                            value: { productId: "truapi-playground.paseo" },
                        },
                    }),
                },
            }),
            "encode getProductContext response",
        );
        fixture.receive(frame);

        expect((await response)._unsafeUnwrap()).toEqual({
            productId: "truapi-playground.paseo",
        });
    });

    it("decodes request domain errors from the versioned response envelope", async () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);

        const response = client.account.getAccount({
            productAccountId: {
                dotNsIdentifier: "foo",
                derivationIndex: { tag: "Index", value: 0 },
            },
        });
        const reason = { tag: "V1", value: { tag: "NotConnected", value: undefined } } as const;
        const frame = unwrap(
            encodeWireMessage({
                requestId: "p:1",
                payload: {
                    traitId: W.ACCOUNT_GET_ACCOUNT.trait,
                    methodId: W.ACCOUNT_GET_ACCOUNT.method,
                    messageType: MESSAGE_TYPE_RESPONSE,
                    value: accountGetResponsePayload({
                        success: false,
                        value: { tag: "Domain", value: reason },
                    }),
                },
            }),
            "encode account_get error response",
        );
        fixture.receive(frame);

        const result = await response;
        expect(result.isErr()).toBe(true);
        expect(result._unsafeUnwrapErr()).toEqual({ tag: "Domain", value: reason });
    });

    it("settles an unknown API request as unsupported from a correlated protocol error", async () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const response = transport.request<undefined, CallErrorValue<never>>({
            ids: { trait: 200, method: 194, kind: "request" },
            payload: new Uint8Array(),
            decodeResponse: () => {
                throw new Error("protocol errors must bypass the method response decoder");
            },
        });
        fixture.receive(unsupportedMessage("p:1", 200, 194));

        expect((await response)._unsafeUnwrapErr()).toEqual({ tag: "Unsupported" });

        const followup = transport.request<string, CallErrorValue<never>>({
            ids: W.LOCAL_STORAGE_READ,
            payload: new Uint8Array(),
            decodeResponse: () => ({ success: true, value: "still connected" }),
        });
        fixture.receive(
            unwrap(
                encodeWireMessage({
                    requestId: "p:2",
                    payload: {
                        traitId: W.LOCAL_STORAGE_READ.trait,
                        methodId: W.LOCAL_STORAGE_READ.method,
                        messageType: MESSAGE_TYPE_RESPONSE,
                        value: new Uint8Array(),
                    },
                }),
                "encode follow-up response",
            ),
        );

        expect((await followup)._unsafeUnwrap()).toBe("still connected");
        expect(fixture.sent).toHaveLength(2);
    });

    it("does not settle a request from an unmatched or mismatched protocol error", async () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const response = transport.request<string, CallErrorValue<never>>({
            ids: { trait: 200, method: 194, kind: "request" },
            payload: new Uint8Array(),
            decodeResponse: () => ({ success: true, value: "supported" }),
        });
        for (const [requestId, traitId, methodId] of [
            // right pair, wrong request id
            ["p:99", 200, 194],
            // right request id, wrong method
            ["p:1", 200, 196],
            // right request id and method but the WRONG TRAIT - under a
            // one-byte discriminant this was indistinguishable from a match
            ["p:1", 201, 194],
        ] as const) {
            fixture.receive(unsupportedMessage(requestId, traitId, methodId));
        }
        fixture.receive(
            unwrap(
                encodeWireMessage({
                    requestId: "p:1",
                    payload: {
                        traitId: 200,
                        methodId: 194,
                        messageType: MESSAGE_TYPE_RESPONSE,
                        value: new Uint8Array(),
                    },
                }),
                "encode supported response",
            ),
        );

        expect((await response)._unsafeUnwrap()).toBe("supported");
        expect(fixture.sent).toHaveLength(1);
    });

    it("reports an unsupported raw subscription only for its matching start", () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const errors: Error[] = [];
        const subscription = transport.subscribeRaw({
            ids: { trait: 7, method: 194, kind: "subscription" },
            payload: new Uint8Array(),
            onReceive: () => {},
            onClose: (error) => errors.push(error),
        });
        // Right trait, wrong method: an error about a different method must
        // not end this subscription.
        fixture.receive(unsupportedMessage(subscription.subscriptionId, 7, 195));
        // Right METHOD, wrong trait. Under a one-byte discriminant these two
        // were indistinguishable; the pair is the whole point, so a trait-8
        // error about method 194 must be ignored here.
        fixture.receive(unsupportedMessage(subscription.subscriptionId, 8, 194));
        // Our actual start pair: this one ends it.
        fixture.receive(unsupportedMessage(subscription.subscriptionId, 7, 194));
        subscription.unsubscribe();

        expect(errors).toHaveLength(1);
        expect(errors[0]).toBeInstanceOf(UnsupportedMessageError);
        const unsupported = errors[0] as UnsupportedMessageError;
        expect({
            name: unsupported.name,
            message: unsupported.message,
            traitId: unsupported.traitId,
            methodId: unsupported.methodId,
        }).toEqual({
            name: "UnsupportedMessageError",
            message: "Peer does not support wire message (7, 194)",
            traitId: 7,
            methodId: 194,
        });
        expect(fixture.sent).toHaveLength(1);
    });

    it("terminates a generated subscription when its API is unsupported", () => {
        const fixture = providerFixture();
        const client = createClient(createTransport(fixture.provider));
        const errors: SubscriptionError[] = [];
        const subscription = client.account
            .connectionStatusSubscribe()
            .subscribe({ error: (error) => errors.push(error) });

        fixture.receive(
            unsupportedMessage(
                subscription.subscriptionId,
                W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.trait,
                W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.method,
            ),
        );

        expect(errors).toHaveLength(1);
        expect(errors[0]).toBeInstanceOf(SubscriptionError);
        expect(errors[0].reason).toBeUndefined();
        expect(errors[0].cause).toBeInstanceOf(UnsupportedMessageError);
        const cause = errors[0].cause as UnsupportedMessageError;
        expect([cause.traitId, cause.methodId]).toEqual([
            W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.trait,
            W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.method,
        ]);
        expect(fixture.sent).toHaveLength(1);
    });

    it("closes the transport for every malformed protocol error shape", async () => {
        // Re-derived for the two-byte address: a valid payload is now 4 bytes,
        // so the old trailing-byte fixture `[0, 0, 194, 0]` decodes cleanly as
        // the pair (194, 0) and would have silently stopped testing anything.
        const malformedPayloads = [
            [new Uint8Array([0, 0]), "expected 4 bytes, received 2"],
            // trait present, method truncated
            [new Uint8Array([0, 0, 194]), "expected 4 bytes, received 3"],
            // one trailing byte past a full pair
            [new Uint8Array([0, 0, 194, 193, 0]), "expected 4 bytes, received 5"],
            [new Uint8Array([1, 0, 194, 193]), "unsupported version 1"],
            [new Uint8Array([0, 1, 194, 193]), "unknown error discriminant 1"],
        ] as const;

        for (const [payload, message] of malformedPayloads) {
            const fixture = providerFixture();
            const transport = createTransport(fixture.provider);
            const response = transport.request<undefined, CallErrorValue<never>>({
                ids: { trait: 200, method: 194, kind: "request" },
                payload: new Uint8Array(),
                decodeResponse: () => ({ success: true, value: undefined }),
            });
            const outcome = Promise.resolve(response);
            fixture.receive(protocolError("p:1", payload));

            await expect(outcome).rejects.toThrow(`Malformed protocol error payload: ${message}`);
            expect(fixture.sent).toHaveLength(1);
        }
    });

    it("rejects an unknown host-initiated message without starting an error loop", () => {
        const fixture = providerFixture();
        createTransport(fixture.provider);
        const incoming = unwrap(
            encodeWireMessage({
                requestId: "h:future",
                payload: {
                    traitId: 200,
                    methodId: 194,
                    messageType: MESSAGE_TYPE_REQUEST,
                    value: new Uint8Array(),
                },
            }),
            "encode unknown host request",
        );

        fixture.receive(incoming);

        expect(fixture.sent.map(toHex)).toEqual([toHex(unsupportedMessage("h:future", 200, 194))]);

        fixture.receive(unsupportedMessage("h:future", 200, 194));
        expect(fixture.sent).toHaveLength(1);
    });

    it("rejects a known host-initiated start when no handler is registered", () => {
        const fixture = providerFixture();
        createTransport(fixture.provider);
        fixture.receive(
            unwrap(
                encodeWireMessage({
                    requestId: "h:known",
                    payload: {
                        traitId: W.CHAT_CUSTOM_MESSAGE_RENDER.trait,
                        methodId: W.CHAT_CUSTOM_MESSAGE_RENDER.method,
                        messageType: MESSAGE_TYPE_START,
                        // No handler is ever registered in this test (no
                        // client is created), so this never reaches a typed
                        // decode of the rest.
                        value: new Uint8Array(),
                    },
                }),
                "encode known unhandled host start",
            ),
        );

        expect(fixture.sent.map(toHex)).toEqual([
            toHex(
                unsupportedMessage(
                    "h:known",
                    W.CHAT_CUSTOM_MESSAGE_RENDER.trait,
                    W.CHAT_CUSTOM_MESSAGE_RENDER.method,
                ),
            ),
        ]);
    });

    it("rejects an unknown message without disturbing its correlated request", async () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const response = transport.request<string, CallErrorValue<never>>({
            ids: W.LOCAL_STORAGE_READ,
            payload: new Uint8Array(),
            decodeResponse: () => ({ success: true, value: "supported" }),
        });
        fixture.receive(
            unwrap(
                encodeWireMessage({
                    requestId: "p:1",
                    payload: {
                        traitId: 200,
                        methodId: 194,
                        messageType: MESSAGE_TYPE_REQUEST,
                        value: new Uint8Array(),
                    },
                }),
                "encode unknown correlated message",
            ),
        );

        expect(fixture.sent.map(toHex)).toEqual([
            toHex(fixture.sent[0]),
            toHex(unsupportedMessage("p:1", 200, 194)),
        ]);

        fixture.receive(
            unwrap(
                encodeWireMessage({
                    requestId: "p:1",
                    payload: {
                        traitId: W.LOCAL_STORAGE_READ.trait,
                        methodId: W.LOCAL_STORAGE_READ.method,
                        messageType: MESSAGE_TYPE_RESPONSE,
                        value: new Uint8Array(),
                    },
                }),
                "encode request response",
            ),
        );
        expect((await response)._unsafeUnwrap()).toBe("supported");
    });

    it("ignores stale frames whose discriminants are known locally", async () => {
        const requestFixture = providerFixture();
        const requestTransport = createTransport(requestFixture.provider);
        const response = requestTransport.request<string, CallErrorValue<never>>({
            ids: W.LOCAL_STORAGE_READ,
            payload: new Uint8Array(),
            decodeResponse: () => ({ success: true, value: "done" }),
        });
        const responseFrame = unwrap(
            encodeWireMessage({
                requestId: "p:1",
                payload: {
                    traitId: W.LOCAL_STORAGE_READ.trait,
                    methodId: W.LOCAL_STORAGE_READ.method,
                    messageType: MESSAGE_TYPE_RESPONSE,
                    value: new Uint8Array(),
                },
            }),
            "encode response",
        );
        requestFixture.receive(responseFrame);
        expect((await response)._unsafeUnwrap()).toBe("done");
        requestFixture.receive(responseFrame);
        expect(requestFixture.sent).toHaveLength(1);

        const subscriptionFixture = providerFixture();
        const subscriptionTransport = createTransport(subscriptionFixture.provider);
        const received: Uint8Array[] = [];
        const subscription = subscriptionTransport.subscribeRaw({
            ids: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE,
            payload: new Uint8Array(),
            onReceive: (payload) => received.push(payload),
        });
        subscription.unsubscribe();
        // Receive and Interrupt now share one address; both are distinguished
        // by `messageType`, not anything inside `value` — and since the
        // subscription is already gone, `value` is never decoded at all.
        for (const messageType of [MESSAGE_TYPE_RECEIVE, MESSAGE_TYPE_INTERRUPT]) {
            subscriptionFixture.receive(
                unwrap(
                    encodeWireMessage({
                        requestId: subscription.subscriptionId,
                        payload: {
                            traitId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.trait,
                            methodId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.method,
                            messageType,
                            value: new Uint8Array(),
                        },
                    }),
                    "encode stale subscription frame",
                ),
            );
        }
        expect(received).toEqual([]);
        expect(subscriptionFixture.sent).toHaveLength(2);
    });

    it("logs a protocol violation for a known pair's out-of-range message type", () => {
        const fixture = providerFixture();
        createTransport(fixture.provider);

        const warnings: unknown[][] = [];
        const originalWarn = console.warn;
        console.warn = (...args: unknown[]) => {
            warnings.push(args);
        };
        try {
            fixture.receive(
                unwrap(
                    encodeWireMessage({
                        requestId: "unrelated:1",
                        payload: {
                            traitId: W.LOCAL_STORAGE_READ.trait,
                            methodId: W.LOCAL_STORAGE_READ.method,
                            messageType: 99,
                            value: new Uint8Array(),
                        },
                    }),
                    "encode malformed-messageType frame",
                ),
            );
        } finally {
            console.warn = originalWarn;
        }

        expect(fixture.sent).toHaveLength(0);
        expect(
            warnings.some((args) =>
                String(args[0]).includes("unexpected messageType 99"),
            ),
        ).toBe(true);
    });

    it("auto-responds to an inbound handshake with the versioned-result shape", () => {
        const fixture = providerFixture();
        createTransport(fixture.provider);

        const requestPayload = T.VersionedHostHandshakeRequest.enc({
            tag: "V1",
            value: { codecVersion: 2 },
        });
        const requestFrame = unwrap(
            encodeWireMessage({
                requestId: "h:1",
                payload: {
                    traitId: W.SYSTEM_HANDSHAKE.trait,
                    methodId: W.SYSTEM_HANDSHAKE.method,
                    messageType: MESSAGE_TYPE_REQUEST,
                    value: requestPayload,
                },
            }),
            "encode inbound handshake_request",
        );
        fixture.receive(requestFrame);

        const expectedFrame = unwrap(
            encodeWireMessage({
                requestId: "h:1",
                payload: {
                    traitId: W.SYSTEM_HANDSHAKE.trait,
                    methodId: W.SYSTEM_HANDSHAKE.method,
                    messageType: MESSAGE_TYPE_RESPONSE,
                    value: handshakeResponsePayload({ success: true, value: undefined }),
                },
            }),
            "encode expected handshake_response",
        );
        expect(toHex(fixture.sent[0])).toBe(toHex(expectedFrame));
    });

    it("answers a codec 1 handshake ping with a protocol error and stays usable", () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);

        // A codec 1 host frames its ping as [requestId][u8 id=0][V1][codec=1].
        // Read against the three-byte header (trait, method, messageType)
        // this client now expects, that's trait=0, method=0, messageType=1,
        // with an EMPTY payload -- trait 0 is unassigned either way (real
        // traits start at 1), so this is an ordinary unknown pair, answered
        // with a protocol error like any other, rather than silently dropped
        // on a guess about the sender's codec version.
        const legacyFrame = new Uint8Array([
            ...str.enc("h:1"),
            0x00, // old flat discriminant, read as the trait byte
            0x00, // old V1 tag, read as the method byte
            0x01, // old codecVersion, read as the messageType byte
        ]);
        fixture.receive(legacyFrame);

        expect(fixture.sent.length).toBe(1);
        expect(toHex(fixture.sent[0])).toBe(toHex(unsupportedMessage("h:1", 0, 0)));

        // The transport must survive: a ping it cannot parse is a peer
        // problem, not grounds for tearing down every pending call.
        void client.account.getAccount({ productAccountId: { dotNsIdentifier: "foo", derivationIndex: { tag: "Index", value: 0 } } });
        expect(fixture.sent.length).toBe(2);
    });

    it("ignores a response whose trait does not match the pending request", async () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);

        const response = client.account.getAccount({ productAccountId: { dotNsIdentifier: "foo", derivationIndex: { tag: "Index", value: 0 } } });

        // Right request id, right method id, neighbouring trait: what a whole
        // trait of discriminant skew looks like from the product side.
        const skewed = unwrap(
            encodeWireMessage({
                requestId: "p:1",
                payload: {
                    traitId: W.ACCOUNT_GET_ACCOUNT.trait + 1,
                    methodId: W.ACCOUNT_GET_ACCOUNT.method,
                    messageType: MESSAGE_TYPE_RESPONSE,
                    value: accountGetResponsePayload({
                        success: false,
                        value: {
                            tag: "Domain",
                            value: { tag: "V1", value: { tag: "NotConnected", value: undefined } },
                        },
                    }),
                },
            }),
            "encode skewed account_get response",
        );
        fixture.receive(skewed);

        // The frame is refused rather than mistaken for the real response.
        const settled = await Promise.race([
            response.then(() => "settled" as const),
            Promise.resolve().then(() => "pending" as const),
        ]);
        expect(settled).toBe("pending");
    });

    it("decodes receive frames as wire wrappers and delivers inner values", () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);
        const events: unknown[] = [];

        const sub = client.account
            .connectionStatusSubscribe()
            .subscribe({ next: (value) => events.push(value) });

        const frame = unwrap(
            encodeWireMessage({
                requestId: sub.subscriptionId,
                payload: {
                    traitId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.trait,
                    methodId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.method,
                    messageType: MESSAGE_TYPE_RECEIVE,
                    value: T.VersionedHostAccountConnectionStatusSubscribeItem.enc({
                        tag: "V1",
                        value: "Connected",
                    }),
                },
            }),
            "encode receive",
        );
        fixture.receive(frame);

        expect(events).toEqual(["Connected"]);
    });

    it("buffers a host render start until the product registers its handler", () => {
        const fixture = providerFixture();
        const client = createClient(createTransport(fixture.provider));
        const request: T.ProductChatCustomMessageRenderRequest = {
            messageId: "message-1",
            messageType: "vote",
            payload: "0x0102",
        };
        // Legacy hosts use opaque ids rather than the Rust host's `h:` prefix.
        fixture.receive(rendererStart("legacy-render-1", request));

        const handled: T.ProductChatCustomMessageRenderRequest[] = [];
        client.chat.onCustomMessageRender((value) => {
            handled.push(value);
            return { subscribe: () => ({ unsubscribe() {} }) };
        });

        expect(handled).toEqual([request]);
        expect(fixture.sent).toHaveLength(0);
    });

    it("streams complete replacement trees on the host-owned request id", () => {
        const fixture = providerFixture();
        const client = createClient(createTransport(fixture.provider));
        let observer: { next?: (node: T.CustomRendererNode) => void } = {};
        client.chat.onCustomMessageRender(() => ({
            subscribe(next) {
                observer = next;
                return { unsubscribe() {} };
            },
        }));

        fixture.receive(
            rendererStart("h:7", {
                messageId: "message-7",
                messageType: "vote",
                payload: "0x",
            }),
        );
        const first = { tag: "String", value: { text: "Votes: 1" } } as const;
        const second = { tag: "String", value: { text: "Votes: 2" } } as const;
        observer.next?.(first);
        observer.next?.(second);

        expect(fixture.sent.map(toHex)).toEqual(
            [rendererReceive("h:7", first), rendererReceive("h:7", second)].map(toHex),
        );
    });

    it("declines a render when the handler throws", () => {
        const fixture = providerFixture();
        const client = createClient(createTransport(fixture.provider));
        client.chat.onCustomMessageRender(() => {
            throw new Error("unsupported renderer");
        });

        fixture.receive(
            rendererStart("h:2", {
                messageId: "message-2",
                messageType: "unknown",
                payload: "0x",
            }),
        );

        expect(toHex(fixture.sent[0])).toBe(toHex(rendererInterrupt("h:2")));
    });

    it("declines a render when its handler stream errors", () => {
        const fixture = providerFixture();
        const client = createClient(createTransport(fixture.provider));
        client.chat.onCustomMessageRender(() => ({
            subscribe(observer) {
                observer.error?.(new Error("renderer failed"));
                return { unsubscribe() {} };
            },
        }));

        fixture.receive(
            rendererStart("h:3", {
                messageId: "message-3",
                messageType: "vote",
                payload: "0x",
            }),
        );

        expect(toHex(fixture.sent[0])).toBe(toHex(rendererInterrupt("h:3")));
    });

    it("keeps a completed render alive until the host stops it", () => {
        const fixture = providerFixture();
        const client = createClient(createTransport(fixture.provider));
        let disposed = false;
        client.chat.onCustomMessageRender(() => ({
            subscribe(observer) {
                observer.complete?.();
                return { unsubscribe: () => (disposed = true) };
            },
        }));

        fixture.receive(
            rendererStart("h:4", {
                messageId: "message-4",
                messageType: "vote",
                payload: "0x",
            }),
        );
        expect(fixture.sent).toHaveLength(0);
        expect(disposed).toBe(false);

        fixture.receive(rendererStop("h:4"));
        expect(disposed).toBe(true);
        expect(fixture.sent).toHaveLength(0);
    });

    it("interrupts the oldest buffered render when capacity is exceeded", () => {
        const fixture = providerFixture();
        createClient(createTransport(fixture.provider));
        for (let index = 1; index <= 65; index += 1) {
            fixture.receive(
                rendererStart(`h:${index}`, {
                    messageId: `message-${index}`,
                    messageType: "vote",
                    payload: "0x",
                }),
            );
        }

        expect(fixture.sent).toHaveLength(1);
        expect(toHex(fixture.sent[0])).toBe(toHex(rendererInterrupt("h:1")));
    });

    it("disposes only the stopped render instance", () => {
        const fixture = providerFixture();
        const client = createClient(createTransport(fixture.provider));
        const disposed: string[] = [];
        client.chat.onCustomMessageRender((request) => ({
            subscribe() {
                return { unsubscribe: () => disposed.push(request.messageId) };
            },
        }));
        fixture.receive(
            rendererStart("h:1", {
                messageId: "one",
                messageType: "vote",
                payload: "0x",
            }),
        );
        fixture.receive(
            rendererStart("h:2", {
                messageId: "two",
                messageType: "vote",
                payload: "0x",
            }),
        );

        fixture.receive(rendererStop("h:1"));
        expect(disposed).toEqual(["one"]);
    });

    it("completes the observable on a payloadless interrupt terminator", () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);
        const completions: unknown[][] = [];

        const sub = client.account
            .connectionStatusSubscribe()
            .subscribe({ complete: (...args) => completions.push(args) });

        const frame = unwrap(
            encodeWireMessage({
                requestId: sub.subscriptionId,
                payload: {
                    traitId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.trait,
                    methodId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.method,
                    messageType: MESSAGE_TYPE_INTERRUPT,
                    value: S.Option(S.CallError(T.GenericError)).enc(undefined),
                },
            }),
            "encode interrupt",
        );
        fixture.receive(frame);

        expect(completions).toEqual([[]]);
    });

    it("surfaces a framework-level interrupt as an observable error on a plain subscription", () => {
        // `chat.listSubscribe` has no domain error of its own (unlike
        // `payment.balanceSubscribe` below): its Interrupt carries a bare
        // `CallErrorValue<GenericError>`. A worker-only subscription like this
        // one denied to an app connection, or a malformed start frame, both
        // arrive this way and must surface as a real error, not a silent
        // `.complete()`.
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);
        const completions: unknown[][] = [];
        const errors: Error[] = [];

        const sub = client.chat.listSubscribe().subscribe({
            complete: (...args) => completions.push(args),
            error: (error) => errors.push(error),
        });

        const callError: CallErrorValue<never> = { tag: "Denied" };
        const frame = unwrap(
            encodeWireMessage({
                requestId: sub.subscriptionId,
                payload: {
                    traitId: W.CHAT_LIST_SUBSCRIBE.trait,
                    methodId: W.CHAT_LIST_SUBSCRIBE.method,
                    messageType: MESSAGE_TYPE_INTERRUPT,
                    value: S.Option(S.CallError(T.GenericError)).enc(callError),
                },
            }),
            "encode denied interrupt",
        );
        fixture.receive(frame);

        expect(completions).toEqual([]);
        expect(errors).toHaveLength(1);
        expect(errors[0]).toBeInstanceOf(SubscriptionError);
        expect((errors[0] as SubscriptionError).reason).toEqual(callError);
    });

    it("surfaces a typed payment interrupt as an observable error", () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);
        const completions: boolean[] = [];
        const errors: Error[] = [];

        const sub = client.payment.balanceSubscribe({ request: {} }).subscribe({
            complete: () => completions.push(true),
            error: (error) => errors.push(error),
        });

        const reason = { tag: "PermissionDenied", value: undefined } as const;
        const callError = {
            tag: "Domain",
            value: { tag: "V1", value: reason },
        } as const;
        const frame = unwrap(
            encodeWireMessage({
                requestId: sub.subscriptionId,
                payload: {
                    traitId: W.PAYMENT_BALANCE_SUBSCRIBE.trait,
                    methodId: W.PAYMENT_BALANCE_SUBSCRIBE.method,
                    messageType: MESSAGE_TYPE_INTERRUPT,
                    value: S.Option(
                        S.CallError(T.VersionedHostPaymentBalanceSubscribeError),
                    ).enc(callError),
                },
            }),
            "encode typed payment interrupt",
        );
        fixture.receive(frame);

        expect(completions).toEqual([]);
        expect(errors).toHaveLength(1);
        expect(errors[0]).toBeInstanceOf(SubscriptionError);
        expect((errors[0] as SubscriptionError).reason).toEqual(callError);
        expect(fixture.sent).toHaveLength(1);
    });

    it("uses the same typed-interrupt envelope for RFC0017 coin-payment streams", () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);
        const errors: Error[] = [];

        const sub = client.coinPayment
            .rebalancePurse({ request: { from: 1, to: 2, amount: 1000 } })
            .subscribe({ error: (error) => errors.push(error) });

        const reason = "Denied";
        const callError = {
            tag: "Domain",
            value: { tag: "V1", value: reason },
        } as const;
        const frame = unwrap(
            encodeWireMessage({
                requestId: sub.subscriptionId,
                payload: {
                    traitId: W.COIN_PAYMENT_REBALANCE_PURSE.trait,
                    methodId: W.COIN_PAYMENT_REBALANCE_PURSE.method,
                    messageType: MESSAGE_TYPE_INTERRUPT,
                    value: S.Option(
                        S.CallError(T.VersionedHostCoinPaymentRebalancePurseError),
                    ).enc(callError),
                },
            }),
            "encode typed coin payment interrupt",
        );
        fixture.receive(frame);

        expect(errors).toHaveLength(1);
        expect(errors[0]).toBeInstanceOf(SubscriptionError);
        expect((errors[0] as SubscriptionError).reason).toEqual(callError);
    });

    it("treats a malformed receive payload as terminal and sends _stop", () => {
        // After the error, the generated wrapper sends `_stop` and ignores later
        // receive frames for that subscription.
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);
        const events: unknown[] = [];
        const errors: Error[] = [];

        const sub = client.account.connectionStatusSubscribe().subscribe({
            next: (value) => events.push(value),
            error: (error) => errors.push(error),
        });

        const malformedFrame = unwrap(
            encodeWireMessage({
                requestId: sub.subscriptionId,
                payload: {
                    traitId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.trait,
                    methodId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.method,
                    messageType: MESSAGE_TYPE_RECEIVE,
                    // An out-of-range item wrapper discriminant, so decoding
                    // fails immediately.
                    value: new Uint8Array([0xff]),
                },
            }),
            "encode malformed receive",
        );
        fixture.receive(malformedFrame);

        expect(events).toEqual([]);
        expect(errors).toHaveLength(1);
        expect(errors[0]).toBeInstanceOf(SubscriptionError);
        expect((errors[0] as SubscriptionError).reason).toBeUndefined();
        expect(fixture.sent).toHaveLength(2);

        const expectedStop = unwrap(
            encodeWireMessage({
                requestId: sub.subscriptionId,
                payload: {
                    traitId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.trait,
                    methodId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.method,
                    messageType: MESSAGE_TYPE_STOP,
                    value: new Uint8Array(),
                },
            }),
            "encode stop after malformed receive",
        );
        expect(toHex(fixture.sent[1])).toBe(toHex(expectedStop));

        const validFrame = unwrap(
            encodeWireMessage({
                requestId: sub.subscriptionId,
                payload: {
                    traitId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.trait,
                    methodId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.method,
                    messageType: MESSAGE_TYPE_RECEIVE,
                    value: T.VersionedHostAccountConnectionStatusSubscribeItem.enc({
                        tag: "V1",
                        value: "Connected",
                    }),
                },
            }),
            "encode receive after malformed receive",
        );
        fixture.receive(validFrame);

        expect(events).toEqual([]);
    });

    it("sends _stop on unsubscribe without invoking terminal callbacks locally", () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);
        const completions: boolean[] = [];
        const errors: Error[] = [];

        const sub = client.account.connectionStatusSubscribe().subscribe({
            complete: () => completions.push(true),
            error: (error) => errors.push(error),
        });
        sub.unsubscribe();

        const expectedStop = unwrap(
            encodeWireMessage({
                requestId: sub.subscriptionId,
                payload: {
                    traitId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.trait,
                    methodId: W.ACCOUNT_CONNECTION_STATUS_SUBSCRIBE.method,
                    messageType: MESSAGE_TYPE_STOP,
                    value: new Uint8Array(),
                },
            }),
            "encode explicit unsubscribe stop",
        );
        expect(toHex(fixture.sent[1])).toBe(toHex(expectedStop));
        expect(completions).toEqual([]);
        expect(errors).toEqual([]);
    });

    it("propagates a provider close/error as a terminal observable error", () => {
        const fixture = providerFixture();
        const transport = createTransport(fixture.provider);
        const client = createClient(transport);
        const errors: Error[] = [];

        client.account
            .connectionStatusSubscribe()
            .subscribe({ error: (error) => errors.push(error) });

        const providerError = new Error("provider closed");
        fixture.close(providerError);

        expect(errors).toHaveLength(1);
        expect(errors[0]).toBeInstanceOf(SubscriptionError);
        expect(errors[0].message).toBe("provider closed");
        expect((errors[0] as SubscriptionError).reason).toBeUndefined();
        expect(errors[0].cause).toBe(providerError);
    });
});
