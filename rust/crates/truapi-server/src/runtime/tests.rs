//! Shared runtime fixtures and cross-capability integration tests.

use std::sync::Mutex;
use std::sync::atomic::Ordering;

use parity_scale_codec::Encode;
use truapi::api::{
    Account, Chain, Entropy, Notifications, Permissions, Preimage, ResourceAllocation, Signing,
    System, Theme,
};
use truapi::versioned::account::{
    HostAccountConnectionStatusSubscribeItem, HostAccountCreateProofError,
    HostAccountCreateProofResponse, HostAccountGetAliasError, HostAccountGetAliasResponse,
    HostAccountGetRequest, HostAccountGetResponse, HostAccountRingVrfSignError,
    HostAccountRingVrfSignRequest, HostAccountRingVrfSignResponse, HostAccountSignVrfRequest,
    HostAccountSignVrfResponse, HostGetLegacyAccountsRequest, HostGetLegacyAccountsResponse,
    HostGetUserIdError, HostGetUserIdRequest, HostGetUserIdResponse,
};
use truapi::versioned::chain::{
    RemoteChainInfoError, RemoteChainInfoRequest, RemoteChainInfoResponse,
    RemoteChainTransactionBroadcastError, RemoteChainTransactionBroadcastRequest,
};
use truapi::versioned::entropy::{
    HostDeriveEntropyError, HostDeriveEntropyRequest, HostDeriveEntropyResponse,
};
use truapi::versioned::notifications::{
    HostPushNotificationCancelRequest, HostPushNotificationCancelResponse,
    HostPushNotificationRequest, HostPushNotificationResponse,
};
use truapi::versioned::permissions::{HostDevicePermissionRequest, HostDevicePermissionResponse};
use truapi::versioned::preimage::{
    RemotePreimageLookupSubscribeItem, RemotePreimageLookupSubscribeRequest,
    RemotePreimageSubmitRequest,
};
use truapi::versioned::resource_allocation::{
    HostRequestResourceAllocationError, HostRequestResourceAllocationRequest,
    HostRequestResourceAllocationResponse,
};
use truapi::versioned::signing::{
    HostCreateTransactionError, HostCreateTransactionRequest, HostCreateTransactionResponse,
    HostCreateTransactionWithLegacyAccountError, HostCreateTransactionWithLegacyAccountRequest,
    HostCreateTransactionWithLegacyAccountResponse, HostSignPayloadError, HostSignPayloadRequest,
    HostSignPayloadResponse, HostSignPayloadWithLegacyAccountError,
    HostSignPayloadWithLegacyAccountRequest, HostSignRawError, HostSignRawRequest,
    HostSignRawResponse, HostSignRawWithLegacyAccountError, HostSignRawWithLegacyAccountRequest,
    HostSignRawWithLegacyAccountResponse,
};
use truapi::versioned::system::{
    HostFeatureSupportedRequest, HostFeatureSupportedResponse, HostGetProductContextRequest,
    HostGetProductContextResponse, HostNavigateToError, HostNavigateToRequest,
    HostNavigateToResponse,
};
use truapi::versioned::theme::HostThemeSubscribeItem;
use truapi_platform::{AuthState, CoreStorageKey, PermissionAuthorizationRequest};

use super::*;
use crate::host_logic::product_account::index_bytes;
use crate::host_logic::sso::messages::{RemoteMessage, RemoteMessageData, Response, v1};
use crate::test_support::*;

fn test_product_subtree(product_id: &str) -> [u8; 32] {
    let root = crate::host_logic::product_account::derive_root_keypair_from_entropy(&[0xAB; 16])
        .expect("test entropy derives a root");
    crate::host_logic::product_account::derive_product_subtree_keypair(&root, product_id)
        .expect("test product id derives a subtree")
        .public
        .to_bytes()
}

fn test_product_account_public(product_id: &str, index: u32) -> [u8; 32] {
    derive_product_public_key(test_product_subtree(product_id), index_bytes(index))
        .expect("test subtree derives an account")
}

fn install_pairing_session(host: &ProductRuntimeHost, session: SessionInfo) {
    let product_id =
        normalize_product_identifier(&host.product_id()).expect("test product identifier is valid");
    if session.sso.is_some() {
        host.test_cache_product_subtree(&session, &product_id, test_product_subtree(&product_id));
    }
    host.test_session_state().set_session(session);
}

fn cache_test_product_subtree(host: &ProductRuntimeHost, session: &SessionInfo, product_id: &str) {
    host.test_cache_product_subtree(session, product_id, test_product_subtree(product_id));
}

#[test]
fn preimage_reports_bulletin_allocation_rejection_with_context() {
    assert_eq!(
        bulletin_allowance_error_reason(AuthorityError::Rejected),
        "Bulletin allowance allocation was rejected by the signing host"
    );
}

fn recorded_rpc_methods(sent_rpc: &Mutex<Vec<String>>) -> Vec<String> {
    sent_rpc
        .lock()
        .expect("rpc list mutex poisoned")
        .iter()
        .map(|request| {
            serde_json::from_str::<serde_json::Value>(request).unwrap()["method"]
                .as_str()
                .unwrap()
                .to_string()
        })
        .collect()
}

fn recorded_rpc_method_count(sent_rpc: &Mutex<Vec<String>>, method: &str) -> usize {
    recorded_rpc_methods(sent_rpc)
        .iter()
        .filter(|candidate| candidate.as_str() == method)
        .count()
}

#[test]
fn feature_supported_round_trips_through_runtime() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let request = HostFeatureSupportedRequest::V1(v01::HostFeatureSupportedRequest::Chain {
        genesis_hash: vec![0u8; 32],
    });
    let response = futures::executor::block_on(host.feature_supported(&cx, request)).unwrap();
    let HostFeatureSupportedResponse::V1(inner) = response;
    assert!(inner.supported);
}

#[test]
fn get_product_context_returns_the_runtime_canonical_product_id() {
    for (configured, expected) in [
        (" TrUAPI-Playground.DOT ", "truapi-playground.dot"),
        ("truapi-playground.paseo", "truapi-playground.paseo"),
        ("truapi-playground.testnet", "truapi-playground.testnet"),
        ("localhost", "localhost"),
        ("LOCALHOST:3000", "localhost:3000"),
    ] {
        let host =
            ProductRuntimeHost::new(stub_platform(), runtime_config(configured), test_spawner());
        let response = futures::executor::block_on(
            host.get_product_context(&CallContext::default(), HostGetProductContextRequest::V1),
        )
        .unwrap();
        let HostGetProductContextResponse::V1(context) = response;

        assert_eq!(
            context,
            v01::HostGetProductContextResponse {
                product_id: expected.to_string(),
            },
            "configured product id {configured:?}",
        );
    }
}

#[test]
fn get_chain_info_round_trips_through_runtime() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let request = RemoteChainInfoRequest::V1(v01::RemoteChainInfoRequest {
        chain: v01::ChainIdentifier::AssetHub,
    });
    let response = futures::executor::block_on(host.get_chain_info(&cx, request)).unwrap();
    let RemoteChainInfoResponse::V1(inner) = response;
    assert_eq!(inner.network, "paseo");
    assert_eq!(inner.chain, v01::ChainIdentifier::AssetHub);
    assert_eq!(inner.genesis_hash, [0xaa; 32]);
}

#[test]
fn get_chain_info_unserved_identifier_is_not_supported() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let request = RemoteChainInfoRequest::V1(v01::RemoteChainInfoRequest {
        chain: v01::ChainIdentifier::Bulletin,
    });
    let error = futures::executor::block_on(host.get_chain_info(&cx, request)).unwrap_err();
    assert_eq!(
        error,
        CallError::Domain(RemoteChainInfoError::V1(
            v01::RemoteChainInfoError::NotSupported
        ))
    );
}

/// Records which `ChatPlatform` methods the runtime actually reached.
#[derive(Default)]
struct RecordingChatPlatform {
    registered_bots: Mutex<Vec<String>>,
    created_rooms: Mutex<Vec<String>>,
    posted_rooms: Mutex<Vec<String>>,
    posted_payloads: Mutex<Vec<v01::ChatMessageContent>>,
}

#[truapi::async_trait]
impl truapi_platform::ChatPlatform for RecordingChatPlatform {
    async fn create_chat_room(
        &self,
        _product: &ProductContext,
        request: truapi::latest::HostChatCreateRoomRequest,
    ) -> Result<truapi::latest::HostChatCreateRoomResponse, truapi::latest::HostChatCreateRoomError>
    {
        self.created_rooms
            .lock()
            .expect("created rooms mutex poisoned")
            .push(request.room_id);
        Ok(truapi::latest::HostChatCreateRoomResponse {
            status: v01::ChatRoomRegistrationStatus::New,
        })
    }

    async fn register_chat_bot(
        &self,
        _product: &ProductContext,
        request: truapi::latest::HostChatRegisterBotRequest,
    ) -> Result<truapi::latest::HostChatRegisterBotResponse, truapi::latest::HostChatRegisterBotError>
    {
        self.registered_bots
            .lock()
            .expect("registered bots mutex poisoned")
            .push(request.bot_id);
        Ok(truapi::latest::HostChatRegisterBotResponse {
            status: v01::ChatBotRegistrationStatus::New,
        })
    }

    async fn post_chat_message(
        &self,
        _product: &ProductContext,
        request: truapi::latest::HostChatPostMessageRequest,
    ) -> Result<truapi::latest::HostChatPostMessageResponse, truapi::latest::HostChatPostMessageError>
    {
        self.posted_rooms
            .lock()
            .expect("posted rooms mutex poisoned")
            .push(request.room_id);
        self.posted_payloads
            .lock()
            .expect("posted payloads mutex poisoned")
            .push(request.payload);
        Ok(truapi::latest::HostChatPostMessageResponse {
            message_id: "message-id".to_string(),
        })
    }

    fn subscribe_chat_rooms(
        &self,
        _product: &ProductContext,
    ) -> futures::stream::BoxStream<
        'static,
        Result<truapi::latest::HostChatListSubscribeItem, truapi::latest::GenericError>,
    > {
        Box::pin(futures::stream::empty())
    }
}

#[test]
fn chat_post_message_screens_content_before_it_reaches_a_host() {
    let (host_config, _) = runtime_config("chat.dot");
    let product = ProductContext::new_with_execution(
        "chat.dot".to_string(),
        truapi_platform::ProductExecutionKind::Worker,
    )
    .expect("test chat product context is valid");
    let spawner = test_spawner();
    let platform: Arc<dyn Platform> = stub_platform();
    let services = RuntimeServices::new(
        platform.clone(),
        host_config.host.host_info.clone(),
        host_config.people_chain_genesis_hash,
        host_config.bulletin_chain_genesis_hash,
        spawner.clone(),
    );
    let chat_platform = Arc::new(RecordingChatPlatform::default());
    let pairing_host = PairingHost::new(services.clone(), host_config);
    let mut adapters = crate::host_core::ConnectionAdapters::from_services(&services);
    adapters.chat_platform = Some(chat_platform.clone());
    let host = ProductRuntimeHost::from_services(services, adapters, pairing_host, product);
    install_pairing_session(&host, session_info());

    let post = |payload: v01::ChatMessageContent| {
        futures::executor::block_on(Chat::post_message(
            &host,
            &CallContext::default(),
            HostChatPostMessageRequest::V1(v01::HostChatPostMessageRequest {
                room_id: "support".to_string(),
                payload,
            }),
        ))
    };

    // The screen runs at this entrypoint, not only in the helper: a host
    // must never be handed a scheme it would fetch or open.
    let rejected = post(v01::ChatMessageContent::File(v01::ChatFile {
        url: "javascript:alert(document.cookie)".to_string(),
        file_name: "f".to_string(),
        mime_type: "text/plain".to_string(),
        size_bytes: 1,
        text: None,
    }))
    .expect_err("a javascript: file url must not reach the host");
    assert!(matches!(
        rejected,
        CallError::Domain(HostChatPostMessageError::V1(
            v01::HostChatPostMessageError::Unknown { .. }
        ))
    ));

    // A body over budget reports the size variant the protocol declares.
    let too_large = post(v01::ChatMessageContent::Text {
        text: "x".repeat(truapi_platform::CHAT_BODY_MAX_BYTES + 1),
    })
    .expect_err("an over-budget body must not reach the host");
    assert!(matches!(
        too_large,
        CallError::Domain(HostChatPostMessageError::V1(
            v01::HostChatPostMessageError::MessageTooLarge
        ))
    ));

    // The payload arm of the size variant, which the body arm does not cover.
    let big_payload = post(v01::ChatMessageContent::Custom(v01::ChatCustomMessage {
        message_type: "vote".to_string(),
        payload: vec![0; truapi_platform::CHAT_CUSTOM_PAYLOAD_MAX_BYTES + 1],
    }))
    .expect_err("an over-budget custom payload must not reach the host");
    assert!(matches!(
        big_payload,
        CallError::Domain(HostChatPostMessageError::V1(
            v01::HostChatPostMessageError::MessageTooLarge
        ))
    ));

    // An over-long room id is not an over-large message.
    let long_room = futures::executor::block_on(Chat::post_message(
        &host,
        &CallContext::default(),
        HostChatPostMessageRequest::V1(v01::HostChatPostMessageRequest {
            room_id: "r".repeat(truapi_platform::CHAT_FIELD_MAX_BYTES + 1),
            payload: v01::ChatMessageContent::Text {
                text: "hi".to_string(),
            },
        }),
    ))
    .expect_err("an over-long room id must be rejected");
    assert!(matches!(
        long_room,
        CallError::Domain(HostChatPostMessageError::V1(
            v01::HostChatPostMessageError::Unknown { .. }
        ))
    ));

    assert!(
        chat_platform
            .posted_rooms
            .lock()
            .expect("posted rooms mutex poisoned")
            .is_empty(),
        "nothing rejected may reach the host"
    );

    // The validated value is what the host receives, not the arriving one:
    // running the screen and discarding its result would pass every
    // rejection assertion above.
    post(v01::ChatMessageContent::Reaction(v01::ChatReaction {
        message_id: "  cafe\u{301}  ".to_string(),
        emoji: "\u{1f3b2}".to_string(),
    }))
    .expect("a normalizable reaction is accepted");
    post(v01::ChatMessageContent::File(v01::ChatFile {
        url: "https://example.invalid".to_string(),
        file_name: "f".to_string(),
        mime_type: "text/plain".to_string(),
        size_bytes: 1,
        text: None,
    }))
    .expect("a resolvable file url is accepted");
    assert_eq!(
        chat_platform
            .posted_payloads
            .lock()
            .expect("posted payloads mutex poisoned")
            .as_slice(),
        &[
            v01::ChatMessageContent::Reaction(v01::ChatReaction {
                message_id: "caf\u{e9}".to_string(),
                emoji: "\u{1f3b2}".to_string(),
            }),
            v01::ChatMessageContent::File(v01::ChatFile {
                url: "https://example.invalid/".to_string(),
                file_name: "f".to_string(),
                mime_type: "text/plain".to_string(),
                size_bytes: 1,
                text: None,
            }),
        ]
    );
}

#[test]
fn chat_room_ids_agree_across_create_and_post() {
    let (host_config, _) = runtime_config("chat.dot");
    let product = ProductContext::new_with_execution(
        "chat.dot".to_string(),
        truapi_platform::ProductExecutionKind::Worker,
    )
    .expect("test chat product context is valid");
    let spawner = test_spawner();
    let platform: Arc<dyn Platform> = stub_platform();
    let services = RuntimeServices::new(
        platform.clone(),
        host_config.host.host_info.clone(),
        host_config.people_chain_genesis_hash,
        host_config.bulletin_chain_genesis_hash,
        spawner.clone(),
    );
    let chat_platform = Arc::new(RecordingChatPlatform::default());
    let pairing_host = PairingHost::new(services.clone(), host_config);
    let mut adapters = crate::host_core::ConnectionAdapters::from_services(&services);
    adapters.chat_platform = Some(chat_platform.clone());
    let host = ProductRuntimeHost::from_services(services, adapters, pairing_host, product);
    install_pairing_session(&host, session_info());

    // Precomposed on create, decomposed on post: the host must see one id,
    // or the message lands in a room that does not exist.
    futures::executor::block_on(Chat::create_room(
        &host,
        &CallContext::default(),
        HostChatCreateRoomRequest::V1(v01::HostChatCreateRoomRequest {
            room_id: "caf\u{e9}".to_string(),
            name: "Cafe".to_string(),
            icon: String::new(),
        }),
    ))
    .expect("create_room accepts a normalizable id");

    futures::executor::block_on(Chat::post_message(
        &host,
        &CallContext::default(),
        HostChatPostMessageRequest::V1(v01::HostChatPostMessageRequest {
            room_id: "cafe\u{301}".to_string(),
            payload: v01::ChatMessageContent::Text {
                text: "hello".to_string(),
            },
        }),
    ))
    .expect("post_message accepts the other spelling of the same id");

    let created = chat_platform
        .created_rooms
        .lock()
        .expect("created rooms mutex poisoned")
        .clone();
    let posted = chat_platform
        .posted_rooms
        .lock()
        .expect("posted rooms mutex poisoned")
        .clone();
    assert_eq!(created, posted);

    // create_room screens the same fields register_bot does.
    for (room_id, icon) in [("", ""), ("room\u{202e}", ""), ("room", "javascript:x")] {
        let rejected = futures::executor::block_on(Chat::create_room(
            &host,
            &CallContext::default(),
            HostChatCreateRoomRequest::V1(v01::HostChatCreateRoomRequest {
                room_id: room_id.to_string(),
                name: "Room".to_string(),
                icon: icon.to_string(),
            }),
        ));
        assert!(
            matches!(
                rejected,
                Err(CallError::Domain(HostChatCreateRoomError::V1(
                    v01::HostChatCreateRoomError::Unknown { .. }
                )))
            ),
            "{room_id:?}/{icon:?} must be a domain error, got {rejected:?}"
        );
    }
}

#[test]
fn chat_register_bot_rejects_unsafe_product_fields() {
    let (host_config, _) = runtime_config("chat.dot");
    let product = ProductContext::new_with_execution(
        "chat.dot".to_string(),
        truapi_platform::ProductExecutionKind::Worker,
    )
    .expect("test chat product context is valid");
    let spawner = test_spawner();
    let platform: Arc<dyn Platform> = stub_platform();
    let services = RuntimeServices::new(
        platform.clone(),
        host_config.host.host_info.clone(),
        host_config.people_chain_genesis_hash,
        host_config.bulletin_chain_genesis_hash,
        spawner.clone(),
    );
    let chat_platform = Arc::new(RecordingChatPlatform::default());
    let pairing_host = PairingHost::new(services.clone(), host_config);
    let mut adapters = crate::host_core::ConnectionAdapters::from_services(&services);
    adapters.chat_platform = Some(chat_platform.clone());
    let host = ProductRuntimeHost::from_services(services, adapters, pairing_host, product.clone());
    install_pairing_session(&host, session_info());

    let register = |bot_id: &str, name: &str, icon: &str| {
        futures::executor::block_on(Chat::register_bot(
            &host,
            &CallContext::default(),
            HostChatRegisterBotRequest::V1(v01::HostChatRegisterBotRequest {
                bot_id: bot_id.to_string(),
                name: name.to_string(),
                icon: icon.to_string(),
            }),
        ))
    };

    // A rejected field is a domain error naming the field, not the
    // transport-level `Unsupported` that means "this host has no Chat".
    for (bot_id, name, icon, expected_field) in [
        ("", "Flipper", "", "botId"),
        ("   ", "Flipper", "", "botId"),
        ("flip\u{202e}per", "Flipper", "", "botId"),
        ("flipper", "Flip\u{202e}per", "", "name"),
        ("flipper", "Flipper", "javascript:alert(1)", "icon"),
        ("flipper", "Flipper", "data: text/html,<script>", "icon"),
        ("flipper", "Flipper", "data:image/svg+xml,<svg>", "icon"),
        ("flipper", "Flipper", "file:///etc/passwd", "icon"),
        ("flipper", "Flipper", "//evil.example/x.png", "icon"),
    ] {
        match register(bot_id, name, icon) {
            Err(CallError::Domain(HostChatRegisterBotError::V1(
                v01::HostChatRegisterBotError::Unknown { reason },
            ))) => assert!(
                reason.contains(expected_field),
                "{bot_id:?}/{name:?}/{icon:?} must name {expected_field}, got {reason:?}"
            ),
            other => panic!("{bot_id:?}/{name:?}/{icon:?} must be a domain error: {other:?}"),
        }
    }
    assert!(
        chat_platform
            .registered_bots
            .lock()
            .expect("registered bots mutex poisoned")
            .is_empty(),
        "no rejected field may reach the host"
    );

    // NFD and NFC spellings normalize to one id, so they cannot become two
    // bots that render identically.
    register("cafe\u{301}", "Cafe", "").expect("normalized id is accepted");
    register("caf\u{e9}", "Cafe", "").expect("normalized id is accepted");
    let bots = chat_platform
        .registered_bots
        .lock()
        .expect("registered bots mutex poisoned");
    assert_eq!(bots.len(), 2);
    assert_eq!(bots[0], bots[1]);
}

/// Guards the failure mode that hid `register_bot`: a `Chat` trait method
/// with no `impl` silently falls back to the trait default and answers
/// `unavailable`, while codegen, the wire table and the TS types all still
/// advertise it.
#[test]
fn chat_register_bot_reaches_the_installed_adapter() {
    let (host_config, _) = runtime_config("chat.dot");
    let product = ProductContext::new_with_execution(
        "chat.dot".to_string(),
        truapi_platform::ProductExecutionKind::Worker,
    )
    .expect("test chat product context is valid");
    let spawner = test_spawner();
    let platform: Arc<dyn Platform> = stub_platform();
    let services = RuntimeServices::new(
        platform.clone(),
        host_config.host.host_info.clone(),
        host_config.people_chain_genesis_hash,
        host_config.bulletin_chain_genesis_hash,
        spawner.clone(),
    );
    let chat_platform = Arc::new(RecordingChatPlatform::default());
    let pairing_host = PairingHost::new(services.clone(), host_config);
    let mut adapters = crate::host_core::ConnectionAdapters::from_services(&services);
    adapters.chat_platform = Some(chat_platform.clone());
    let host = ProductRuntimeHost::from_services(
        services.clone(),
        adapters,
        pairing_host,
        product.clone(),
    );
    install_pairing_session(&host, session_info());

    let response = futures::executor::block_on(Chat::register_bot(
        &host,
        &CallContext::default(),
        HostChatRegisterBotRequest::V1(v01::HostChatRegisterBotRequest {
            bot_id: "flipper".to_string(),
            name: "Flipper".to_string(),
            icon: String::new(),
        }),
    ));

    let HostChatRegisterBotResponse::V1(response) =
        response.expect("register_bot must reach the adapter, not fall back to unavailable");
    assert_eq!(response.status, v01::ChatBotRegistrationStatus::New);
    assert_eq!(
        chat_platform
            .registered_bots
            .lock()
            .expect("registered bots mutex poisoned")
            .as_slice(),
        &["flipper"]
    );
}

#[test]
fn chain_follow_ids_are_scoped_per_product_core() {
    let (host_config, product) = runtime_config("same.dot");
    let spawner = test_spawner();
    let platform: Arc<dyn Platform> = stub_platform();
    let services = RuntimeServices::new(
        platform.clone(),
        host_config.host.host_info.clone(),
        host_config.people_chain_genesis_hash,
        host_config.bulletin_chain_genesis_hash,
        spawner.clone(),
    );
    let pairing_host = PairingHost::new(services.clone(), host_config);
    let first = ProductRuntimeHost::from_services(
        services.clone(),
        crate::host_core::ConnectionAdapters::from_services(&services),
        pairing_host.clone(),
        product.clone(),
    );
    let second = ProductRuntimeHost::from_services(
        services.clone(),
        crate::host_core::ConnectionAdapters::from_services(&services),
        pairing_host,
        product,
    );

    assert_eq!(first.follow_id("request-1"), "c1:request-1");
    assert_eq!(second.follow_id("request-1"), "c2:request-1");
}

#[test]
fn bare_localhost_product_allows_dev_product_accounts() {
    let host =
        ProductRuntimeHost::new(stub_platform(), runtime_config("localhost"), test_spawner());

    assert!(host.is_product_account_valid_for_caller("myapp.dot"));
}

#[test]
fn navigate_to_uses_dotns_decision_and_then_platform() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let request = HostNavigateToRequest::V1(v01::HostNavigateToRequest {
        url: "mytestapp.dot".to_string(),
    });
    let response = futures::executor::block_on(host.navigate_to(&cx, request)).unwrap();
    assert_eq!(response, HostNavigateToResponse::V1);
}

#[test]
fn navigate_to_rejects_empty_input_without_calling_platform() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let request = HostNavigateToRequest::V1(v01::HostNavigateToRequest {
        url: "".to_string(),
    });
    let err = futures::executor::block_on(host.navigate_to(&cx, request)).unwrap_err();
    match err {
        CallError::Domain(HostNavigateToError::V1(v01::HostNavigateToError::Unknown {
            ..
        })) => {}
        other => panic!("expected Unknown navigate error, got {other:?}"),
    }
}

#[test]
fn navigate_to_external_denies_without_a_remote_grant() {
    let platform = Arc::new(StubPlatform {
        remote_permission_denied: true,
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    let cx = CallContext::default();
    let request = HostNavigateToRequest::V1(v01::HostNavigateToRequest {
        url: "https://example.com/page".to_string(),
    });

    let err = futures::executor::block_on(host.navigate_to(&cx, request)).unwrap_err();
    match err {
        CallError::Domain(HostNavigateToError::V1(v01::HostNavigateToError::PermissionDenied)) => {}
        other => panic!("expected navigate permission denial, got {other:?}"),
    }
    assert!(
        platform
            .navigations
            .lock()
            .expect("navigation list mutex poisoned")
            .is_empty(),
        "a denied navigation must not reach the platform"
    );
}

#[test]
fn navigate_to_external_prompts_for_the_host_then_reuses_the_grant() {
    let platform = Arc::new(StubPlatform::default());
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    let cx = CallContext::default();

    for path in ["https://example.com/first", "https://example.com/second"] {
        let request = HostNavigateToRequest::V1(v01::HostNavigateToRequest {
            url: path.to_string(),
        });
        assert_eq!(
            futures::executor::block_on(host.navigate_to(&cx, request)).unwrap(),
            HostNavigateToResponse::V1
        );
    }

    let asked = platform
        .remote_permission_requests
        .lock()
        .expect("remote permission list mutex poisoned")
        .clone();
    assert_eq!(
        asked,
        vec![v01::RemotePermissionRequest {
            permission: v01::RemotePermission::Remote {
                domains: vec!["example.com".to_string()],
            },
        }],
        "the gate asks once, for the target host, and the grant covers later paths"
    );
    assert_eq!(
        platform
            .navigations
            .lock()
            .expect("navigation list mutex poisoned")
            .len(),
        2
    );
}

#[test]
fn navigate_to_dotns_and_localhost_bypass_the_remote_gate() {
    // Both resolve back into the host's own product surface, so a denied
    // remote permission must not block in-ecosystem navigation.
    let platform = Arc::new(StubPlatform {
        remote_permission_denied: true,
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    let cx = CallContext::default();

    for url in ["mytestapp.dot", "localhost:3000"] {
        let request = HostNavigateToRequest::V1(v01::HostNavigateToRequest {
            url: url.to_string(),
        });
        assert_eq!(
            futures::executor::block_on(host.navigate_to(&cx, request)).unwrap(),
            HostNavigateToResponse::V1,
            "{url} must not consume a remote grant"
        );
    }
    assert!(
        platform
            .remote_permission_requests
            .lock()
            .expect("remote permission list mutex poisoned")
            .is_empty()
    );
}

#[test]
fn navigate_to_handoff_schemes_bypass_the_remote_gate() {
    // Only `http(s)` reaches a domain a grant can name. The other allowed
    // schemes hand the URL to another app, so a denying platform must not
    // turn them into a permission error.
    let platform = Arc::new(StubPlatform {
        remote_permission_denied: true,
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    let cx = CallContext::default();

    let handoffs = [
        "mailto:someone@example.com",
        "tel:+15551234567",
        "polkadot://1exampleaddress",
        "dot:transfer",
    ];
    for url in handoffs {
        let request = HostNavigateToRequest::V1(v01::HostNavigateToRequest {
            url: url.to_string(),
        });
        assert_eq!(
            futures::executor::block_on(host.navigate_to(&cx, request)).unwrap(),
            HostNavigateToResponse::V1,
            "{url} has no authorizable domain and must reach the platform"
        );
    }
    assert!(
        platform
            .remote_permission_requests
            .lock()
            .expect("remote permission list mutex poisoned")
            .is_empty(),
        "a hostless scheme must not consume a grant"
    );
    assert_eq!(
        platform
            .navigations
            .lock()
            .expect("navigation list mutex poisoned")
            .len(),
        handoffs.len()
    );
}

#[test]
fn push_notification_delegates_payload_and_returns_host_id() {
    let pushed_notifications = Arc::new(Mutex::new(Vec::new()));
    let platform = Arc::new(StubPlatform {
        notification_id: 42,
        pushed_notifications: pushed_notifications.clone(),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform, test_spawner());
    let cx = CallContext::default();
    let request = HostPushNotificationRequest::V1(v01::HostPushNotificationRequest {
        text: "Hello".to_string(),
        deeplink: Some("https://example.invalid/launch".to_string()),
        scheduled_at: Some(1_776_144_000_000),
    });

    let response = futures::executor::block_on(host.send_push_notification(&cx, request)).unwrap();

    assert_eq!(
        response,
        HostPushNotificationResponse::V1(v01::HostPushNotificationResponse { id: 42 })
    );
    assert_eq!(
        pushed_notifications
            .lock()
            .expect("notification list mutex poisoned")
            .as_slice(),
        &[v01::HostPushNotificationRequest {
            text: "Hello".to_string(),
            deeplink: Some("https://example.invalid/launch".to_string()),
            scheduled_at: Some(1_776_144_000_000),
        }]
    );
}

#[test]
fn cancel_notification_delegates_host_id() {
    let cancelled_notifications = Arc::new(Mutex::new(Vec::new()));
    let platform = Arc::new(StubPlatform {
        cancelled_notifications: cancelled_notifications.clone(),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform, test_spawner());
    let cx = CallContext::default();
    let request =
        HostPushNotificationCancelRequest::V1(v01::HostPushNotificationCancelRequest { id: 42 });

    let response =
        futures::executor::block_on(host.cancel_push_notification(&cx, request)).unwrap();

    assert_eq!(response, HostPushNotificationCancelResponse::V1);
    assert_eq!(
        cancelled_notifications
            .lock()
            .expect("notification cancellation list mutex poisoned")
            .as_slice(),
        &[42]
    );
}

#[test]
fn get_account_requires_session() {
    let host =
        ProductRuntimeHost::new(stub_platform(), runtime_config("myapp.dot"), test_spawner());
    let cx = CallContext::default();
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: v01::ProductAccountId {
            dot_ns_identifier: "myapp.dot".to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        },
    });
    let err = futures::executor::block_on(host.get_account(&cx, request)).unwrap_err();
    assert!(matches!(
        err,
        CallError::Domain(HostAccountGetError::V1(
            v01::HostAccountGetError::NotConnected
        ))
    ));
}

#[test]
fn get_account_maps_subtree_disconnect_race_to_not_connected() {
    let session = sso_session_info();
    let platform = Arc::new(StubPlatform {
        sso_response_script: Some(sso_peer_disconnect_response_script(&session)),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new(platform, runtime_config("myapp.dot"), test_spawner());
    host.test_session_state().set_session(session);
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: account_id("myapp.dot", 0),
    });

    let err = futures::executor::block_on(host.get_account(&CallContext::default(), request))
        .unwrap_err();

    assert!(matches!(
        err,
        CallError::Domain(HostAccountGetError::V1(
            v01::HostAccountGetError::NotConnected
        ))
    ));
}

#[test]
fn get_account_rejects_invalid_product_identifier() {
    let host =
        ProductRuntimeHost::new(stub_platform(), runtime_config("myapp.dot"), test_spawner());
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: v01::ProductAccountId {
            dot_ns_identifier: "example.com".to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        },
    });
    let err = futures::executor::block_on(host.get_account(&cx, request)).unwrap_err();
    assert!(matches!(
        err,
        CallError::Domain(HostAccountGetError::V1(
            v01::HostAccountGetError::DomainNotValid
        ))
    ));
}

#[test]
fn get_account_other_product_rejects_when_user_declines() {
    let platform = stub_platform();
    let host = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: v01::ProductAccountId {
            dot_ns_identifier: "other.dot".to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        },
    });
    let err = futures::executor::block_on(host.get_account(&cx, request)).unwrap_err();
    assert!(matches!(
        err,
        CallError::Domain(HostAccountGetError::V1(v01::HostAccountGetError::Rejected))
    ));
    assert_eq!(
        platform
            .account_access_reviews
            .lock()
            .expect("account access review list mutex poisoned")
            .as_slice(),
        &[AccountAccessReview {
            requesting_product_id: "myapp.dot".to_string(),
            target_product_id: "other.dot".to_string(),
        }]
    );
}

#[test]
fn get_account_other_product_maps_confirmation_failure_to_host_failure() {
    let host = ProductRuntimeHost::new(
        Arc::new(StubPlatform {
            account_access_error: Some("modal failed"),
            ..Default::default()
        }),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: v01::ProductAccountId {
            dot_ns_identifier: "other.dot".to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        },
    });
    let err = futures::executor::block_on(host.get_account(&cx, request)).unwrap_err();
    assert!(matches!(err, CallError::HostFailure { reason } if reason.contains("modal failed")));
}

#[test]
fn get_account_other_product_accepts_confirmation_then_derives_key() {
    let host = ProductRuntimeHost::new(
        Arc::new(StubPlatform {
            account_access_confirmed: true,
            ..Default::default()
        }),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    let session = sso_session_info();
    install_pairing_session(&host, session.clone());
    cache_test_product_subtree(&host, &session, "other.dot");
    let cx = CallContext::default();
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: v01::ProductAccountId {
            dot_ns_identifier: "other.dot".to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        },
    });
    let response = futures::executor::block_on(host.get_account(&cx, request)).unwrap();
    let HostAccountGetResponse::V1(inner) = response;
    assert_eq!(
        inner.account.public_key,
        test_product_account_public("other.dot", 0).to_vec()
    );
}

#[test]
fn get_account_derives_rfc0022_product_key() {
    let host =
        ProductRuntimeHost::new(stub_platform(), runtime_config("myapp.dot"), test_spawner());
    install_pairing_session(&host, sso_session_info());
    let cx = CallContext::default();
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: v01::ProductAccountId {
            dot_ns_identifier: "myapp.dot".to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        },
    });
    let response = futures::executor::block_on(host.get_account(&cx, request)).unwrap();
    let HostAccountGetResponse::V1(inner) = response;
    assert_eq!(
        hex::encode(inner.account.public_key),
        "1c1ae478b564572f806ffa6352b4273d612beb01610b19f4e5bf444521cd5b5c"
    );
}

#[test]
fn get_account_own_product_prompts_and_rejects_on_a_cold_subtree() {
    let host = ProductRuntimeHost::new(
        Arc::new(StubPlatform {
            product_subtree_denied: true,
            ..Default::default()
        }),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    // Session without a cached subtree: resolving it must reach the
    // Account Holder, which is the one point the consent prompt fires.
    host.test_session_state().set_session(sso_session_info());
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: account_id("myapp.dot", 0),
    });

    let err = futures::executor::block_on(host.get_account(&CallContext::default(), request))
        .unwrap_err();

    assert!(matches!(
        err,
        CallError::Domain(HostAccountGetError::V1(v01::HostAccountGetError::Rejected))
    ));
}

#[test]
fn get_account_own_product_skips_the_prompt_when_the_subtree_is_cached() {
    // denied would reject if the prompt fired; a warm cache must not prompt.
    let host = ProductRuntimeHost::new(
        Arc::new(StubPlatform {
            product_subtree_denied: true,
            ..Default::default()
        }),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, sso_session_info());
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: account_id("myapp.dot", 0),
    });

    let response = futures::executor::block_on(host.get_account(&CallContext::default(), request))
        .expect("a cached subtree resolves without prompting");
    let HostAccountGetResponse::V1(inner) = response;
    assert_eq!(
        inner.account.public_key,
        test_product_account_public("myapp.dot", 0).to_vec()
    );
}

#[test]
fn remote_authority_call_bounds_a_call_that_never_unwinds() {
    let mut cx = CallContext::default();
    cx.set_timeout(Duration::from_millis(1));
    // A call that never completes and never observes the token, standing in
    // for one parked in the un-cancellable statement-store setup. The old
    // code awaited it after cancelling and hung; it must now be dropped at
    // the grace and return a bounded timeout.
    let call = futures::future::pending::<Result<(), AuthorityError>>();

    let err = futures::executor::block_on(remote_authority_call(&cx, call))
        .expect_err("a never-unwinding call is bounded by the deadline plus grace");

    assert!(matches!(err, AuthorityError::Cancelled(_)));
}

#[test]
fn get_account_normalizes_product_identifier_before_deriving() {
    let host =
        ProductRuntimeHost::new(stub_platform(), runtime_config("MyApp.DOT"), test_spawner());
    install_pairing_session(&host, sso_session_info());
    let cx = CallContext::default();
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: v01::ProductAccountId {
            dot_ns_identifier: "MyApp.DOT".to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        },
    });
    let response = futures::executor::block_on(host.get_account(&cx, request)).unwrap();
    let HostAccountGetResponse::V1(inner) = response;
    assert_eq!(
        hex::encode(inner.account.public_key),
        "1c1ae478b564572f806ffa6352b4273d612beb01610b19f4e5bf444521cd5b5c"
    );
}

#[test]
fn get_account_localhost_product_prompts_for_other_product_identifier() {
    let host = ProductRuntimeHost::new(
        Arc::new(StubPlatform {
            account_access_confirmed: true,
            ..Default::default()
        }),
        runtime_config("localhost:3000"),
        test_spawner(),
    );
    let session = sso_session_info();
    install_pairing_session(&host, session.clone());
    cache_test_product_subtree(&host, &session, "myapp.dot");
    let cx = CallContext::default();
    let request = HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: v01::ProductAccountId {
            dot_ns_identifier: "myapp.dot".to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        },
    });
    let response = futures::executor::block_on(host.get_account(&cx, request)).unwrap();
    let HostAccountGetResponse::V1(inner) = response;
    assert_eq!(
        hex::encode(inner.account.public_key),
        "1c1ae478b564572f806ffa6352b4273d612beb01610b19f4e5bf444521cd5b5c"
    );
}

#[test]
fn get_account_alias_requires_session() {
    let host =
        ProductRuntimeHost::new(stub_platform(), runtime_config("myapp.dot"), test_spawner());
    let cx = CallContext::default();
    let err = futures::executor::block_on(
        host.get_account_alias(&cx, account_alias_request("myapp.dot")),
    )
    .unwrap_err();
    assert!(matches!(
        err,
        CallError::Domain(HostAccountGetAliasError::V1(
            v01::HostAccountGetAliasError::Rejected
        ))
    ));
}

#[test]
fn get_account_alias_forwards_without_pairing_host_confirmation() {
    let session = sso_session_info();
    let platform = Arc::new(StubPlatform {
        sso_response_script: Some(sso_success_response_script(
            &session,
            RemoteMessage {
                message_id: "wallet-alias-1".to_string(),
                data: RemoteMessageData::V1(v1::RemoteMessage::GetAccountAliasResponse(Response {
                    responding_to: "alias-1".to_string(),
                    payload: Ok(v01::ContextualAlias {
                        context: [9; 32],
                        alias: vec![1, 2, 3],
                    }),
                })),
            },
        )),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    let cx = CallContext::with_request_id("alias-1".to_string());
    let response = futures::executor::block_on(
        host.get_account_alias(&cx, account_alias_request("myapp.dot")),
    )
    .unwrap();
    let HostAccountGetAliasResponse::V1(inner) = response;
    assert_eq!(inner.context, [9; 32]);
    assert_eq!(inner.alias, vec![1, 2, 3]);
    let message = submitted_remote_message(&platform, &session);
    let RemoteMessageData::V1(v1::RemoteMessage::GetAccountAliasRequest(request)) = message.data
    else {
        panic!("expected ring VRF alias request");
    };
    assert_eq!(request.calling_product_id, "myapp.dot");
    assert_eq!(request.context.product_id, "myapp.dot");
    assert_eq!(request.ring_location.chain_id, [1; 32]);
}

#[test]
fn create_account_proof_requires_session() {
    let host =
        ProductRuntimeHost::new(stub_platform(), runtime_config("myapp.dot"), test_spawner());
    let cx = CallContext::default();
    let err = futures::executor::block_on(
        host.create_account_proof(&cx, create_proof_request("myapp.dot")),
    )
    .unwrap_err();
    assert!(matches!(
        err,
        CallError::Domain(HostAccountCreateProofError::V1(
            v01::HostAccountCreateProofError::Rejected
        ))
    ));
}

#[test]
fn create_account_proof_returns_sso_proof() {
    let session = sso_session_info();
    let platform = Arc::new(StubPlatform {
        sso_response_script: Some(sso_success_response_script(
            &session,
            RemoteMessage {
                message_id: "wallet-proof-1".to_string(),
                data: RemoteMessageData::V1(v1::RemoteMessage::CreateAccountProofResponse(
                    Response {
                        responding_to: "proof-1".to_string(),
                        payload: Ok(v01::HostAccountCreateProofResponse {
                            proof: vec![0xaa, 0xbb],
                            contextual_alias: v01::ContextualAlias {
                                context: [9; 32],
                                alias: vec![1, 2, 3],
                            },
                            ring_index: 5,
                            ring_revision: 7,
                        }),
                    },
                )),
            },
        )),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    let cx = CallContext::with_request_id("proof-1".to_string());
    let response = futures::executor::block_on(
        host.create_account_proof(&cx, create_proof_request("myapp.dot")),
    )
    .unwrap();
    let HostAccountCreateProofResponse::V1(inner) = response;
    assert_eq!(inner.proof, vec![0xaa, 0xbb]);
    assert_eq!(inner.ring_index, 5);
    assert_eq!(inner.ring_revision, 7);
    let message = submitted_remote_message(&platform, &session);
    let RemoteMessageData::V1(v1::RemoteMessage::CreateAccountProofRequest(request)) = message.data
    else {
        panic!("expected ring VRF proof request");
    };
    assert_eq!(request.calling_product_id, "myapp.dot");
    assert_eq!(request.context.product_id, "myapp.dot");
    assert_eq!(request.message, vec![4, 5, 6]);
}

#[test]
fn create_account_proof_maps_not_member_error() {
    let session = sso_session_info();
    let platform = Arc::new(StubPlatform {
        sso_response_script: Some(sso_success_response_script(
            &session,
            RemoteMessage {
                message_id: "wallet-proof-1".to_string(),
                data: RemoteMessageData::V1(v1::RemoteMessage::CreateAccountProofResponse(
                    Response {
                        responding_to: "proof-1".to_string(),
                        payload: Err(RingVrfError::NotMember),
                    },
                )),
            },
        )),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, session);
    let cx = CallContext::with_request_id("proof-1".to_string());
    let err = futures::executor::block_on(
        host.create_account_proof(&cx, create_proof_request("myapp.dot")),
    )
    .unwrap_err();
    assert!(matches!(
        err,
        CallError::Domain(HostAccountCreateProofError::V1(
            v01::HostAccountCreateProofError::NotMember
        ))
    ));
}

#[test]
fn get_legacy_accounts_returns_empty_when_connected() {
    let host = ProductRuntimeHost::new(
        stub_platform(),
        runtime_config("localhost:3000"),
        test_spawner(),
    );
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();
    let response = futures::executor::block_on(
        host.get_legacy_accounts(&cx, HostGetLegacyAccountsRequest::V1),
    )
    .unwrap();
    let HostGetLegacyAccountsResponse::V1(inner) = response;
    assert!(inner.accounts.is_empty());
}

#[test]
fn get_legacy_accounts_returns_empty_when_disconnected() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let response = futures::executor::block_on(
        host.get_legacy_accounts(&cx, HostGetLegacyAccountsRequest::V1),
    )
    .unwrap();
    let HostGetLegacyAccountsResponse::V1(inner) = response;
    assert!(inner.accounts.is_empty());
}

#[test]
fn get_user_id_returns_primary_username() {
    let platform = Arc::new(StubPlatform {
        identity_disclosure_confirmed: true,
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();
    let response =
        futures::executor::block_on(host.get_user_id(&cx, HostGetUserIdRequest::V1)).unwrap();
    let HostGetUserIdResponse::V1(inner) = response;
    assert_eq!(inner.primary_username, "Alice Smith");
    assert_eq!(platform.identity_disclosure_calls.load(Ordering::SeqCst), 1);
}

#[test]
fn get_user_id_caches_identity_disclosure_grant() {
    let platform = Arc::new(StubPlatform {
        identity_disclosure_confirmed: true,
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();

    futures::executor::block_on(host.get_user_id(&cx, HostGetUserIdRequest::V1)).unwrap();
    futures::executor::block_on(host.get_user_id(&cx, HostGetUserIdRequest::V1)).unwrap();

    assert_eq!(platform.identity_disclosure_calls.load(Ordering::SeqCst), 1);
    let status = futures::executor::block_on(
        host.permission_authorization_status(PermissionAuthorizationRequest::IdentityDisclosure),
    )
    .unwrap();
    assert_eq!(status, PermissionAuthorizationStatus::Authorized);
}

#[test]
fn get_user_id_caches_identity_disclosure_denial() {
    let platform = Arc::new(StubPlatform::default());
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();

    let first =
        futures::executor::block_on(host.get_user_id(&cx, HostGetUserIdRequest::V1)).unwrap_err();
    let second =
        futures::executor::block_on(host.get_user_id(&cx, HostGetUserIdRequest::V1)).unwrap_err();

    assert_eq!(platform.identity_disclosure_calls.load(Ordering::SeqCst), 1);
    assert!(matches!(
        first,
        CallError::Domain(HostGetUserIdError::V1(
            v01::HostGetUserIdError::PermissionDenied
        ))
    ));
    assert!(matches!(
        second,
        CallError::Domain(HostGetUserIdError::V1(
            v01::HostGetUserIdError::PermissionDenied
        ))
    ));
    let status = futures::executor::block_on(
        host.permission_authorization_status(PermissionAuthorizationRequest::IdentityDisclosure),
    )
    .unwrap();
    assert_eq!(status, PermissionAuthorizationStatus::Denied);
}

#[test]
fn get_user_id_dismissed_identity_disclosure_stays_not_determined() {
    let platform = Arc::new(StubPlatform {
        identity_disclosure_error: Some("dismissed"),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();

    let first =
        futures::executor::block_on(host.get_user_id(&cx, HostGetUserIdRequest::V1)).unwrap_err();
    let second =
        futures::executor::block_on(host.get_user_id(&cx, HostGetUserIdRequest::V1)).unwrap_err();

    assert_eq!(platform.identity_disclosure_calls.load(Ordering::SeqCst), 2);
    assert!(matches!(
        first,
        CallError::Domain(HostGetUserIdError::V1(
            v01::HostGetUserIdError::PermissionDenied
        ))
    ));
    assert!(matches!(
        second,
        CallError::Domain(HostGetUserIdError::V1(
            v01::HostGetUserIdError::PermissionDenied
        ))
    ));
    let status = futures::executor::block_on(
        host.permission_authorization_status(PermissionAuthorizationRequest::IdentityDisclosure),
    )
    .unwrap();
    assert_eq!(status, PermissionAuthorizationStatus::NotDetermined);
}

#[test]
fn get_user_id_checks_identity_disclosure_before_username() {
    let platform = Arc::new(StubPlatform::default());
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    let mut session = session_info();
    session.full_username = None;
    session.lite_username = None;
    install_pairing_session(&host, session);
    let cx = CallContext::default();

    let err =
        futures::executor::block_on(host.get_user_id(&cx, HostGetUserIdRequest::V1)).unwrap_err();

    assert!(matches!(
        err,
        CallError::Domain(HostGetUserIdError::V1(
            v01::HostGetUserIdError::PermissionDenied
        ))
    ));
    assert_eq!(platform.identity_disclosure_calls.load(Ordering::SeqCst), 1);
}

#[test]
fn get_user_id_reports_missing_username_after_identity_disclosure() {
    let platform = Arc::new(StubPlatform {
        identity_disclosure_confirmed: true,
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    let mut session = session_info();
    session.full_username = None;
    session.lite_username = None;
    install_pairing_session(&host, session);
    let cx = CallContext::default();

    let err =
        futures::executor::block_on(host.get_user_id(&cx, HostGetUserIdRequest::V1)).unwrap_err();

    assert!(matches!(
        err,
        CallError::Domain(HostGetUserIdError::V1(
            v01::HostGetUserIdError::Unknown { ref reason }
        )) if reason == "No primary username for this session"
    ));
    assert_eq!(platform.identity_disclosure_calls.load(Ordering::SeqCst), 1);
}

#[test]
fn get_user_id_respects_pre_authorized_identity_disclosure() {
    let platform = Arc::new(StubPlatform::default());
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();
    futures::executor::block_on(host.set_permission_authorization_status(
        PermissionAuthorizationRequest::IdentityDisclosure,
        PermissionAuthorizationStatus::Authorized,
    ))
    .unwrap();

    let response =
        futures::executor::block_on(host.get_user_id(&cx, HostGetUserIdRequest::V1)).unwrap();
    let HostGetUserIdResponse::V1(inner) = response;
    assert_eq!(inner.primary_username, "Alice Smith");
    assert_eq!(platform.identity_disclosure_calls.load(Ordering::SeqCst), 0);
}

#[test]
fn derive_entropy_matches_dotli_vector() {
    let host =
        ProductRuntimeHost::new(stub_platform(), runtime_config("myapp.dot"), test_spawner());
    let mut session = sso_session_info();
    session.root_entropy_source = session_info().root_entropy_source;
    install_pairing_session(&host, session);
    let cx = CallContext::default();
    let request = HostDeriveEntropyRequest::V1(v01::HostDeriveEntropyRequest {
        context: b"product-key".to_vec(),
    });
    let response = futures::executor::block_on(host.derive(&cx, request)).unwrap();
    let HostDeriveEntropyResponse::V1(inner) = response;
    assert_eq!(
        hex::encode(inner.entropy),
        "ab1887248c9de3cf4b8c5a255782796d3d35a98c8eb2d7df61a410db8b14da36"
    );
}

#[test]
fn derive_entropy_requires_session() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let request = HostDeriveEntropyRequest::V1(v01::HostDeriveEntropyRequest {
        context: b"product-key".to_vec(),
    });
    let err = futures::executor::block_on(host.derive(&cx, request)).unwrap_err();
    match err {
        CallError::Domain(HostDeriveEntropyError::V1(v01::HostDeriveEntropyError::Unknown {
            reason,
        })) => assert_eq!(reason, "Not connected"),
        other => panic!("expected Unknown entropy error, got {other:?}"),
    }
}

#[test]
fn derive_entropy_requires_secret() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let mut session = sso_session_info();
    session.root_entropy_source = None;
    install_pairing_session(&host, session);
    let cx = CallContext::default();
    let request = HostDeriveEntropyRequest::V1(v01::HostDeriveEntropyRequest {
        context: b"product-key".to_vec(),
    });
    let err = futures::executor::block_on(host.derive(&cx, request)).unwrap_err();
    match err {
        CallError::Domain(HostDeriveEntropyError::V1(v01::HostDeriveEntropyError::Unknown {
            reason,
        })) => assert_eq!(reason, "Session secret missing"),
        other => panic!("expected Unknown entropy error, got {other:?}"),
    }
}

#[test]
fn derive_entropy_rejects_empty_context_like_dotli_key() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let mut session = sso_session_info();
    session.root_entropy_source = session_info().root_entropy_source;
    install_pairing_session(&host, session);
    let cx = CallContext::default();
    let request = HostDeriveEntropyRequest::V1(v01::HostDeriveEntropyRequest { context: vec![] });
    let err = futures::executor::block_on(host.derive(&cx, request)).unwrap_err();
    match err {
        CallError::Domain(HostDeriveEntropyError::V1(v01::HostDeriveEntropyError::Unknown {
            reason,
        })) => assert_eq!(reason, "\"key\" must be between 1 and 32 bytes, got 0"),
        other => panic!("expected Unknown entropy error, got {other:?}"),
    }
}

#[test]
fn preimage_submit_requires_session_first() {
    let host = ProductRuntimeHost::new_compat_with_bulletin(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let request = RemotePreimageSubmitRequest::V1(vec![1, 2, 3]);

    let err = futures::executor::block_on(Preimage::submit(&host, &cx, request)).unwrap_err();

    match err {
        CallError::Domain(RemotePreimageSubmitError::V1(v01::PreimageSubmitError::Unknown {
            reason,
        })) => assert_eq!(reason, "No active session"),
        other => panic!("expected preimage session error, got {other:?}"),
    }
}

#[test]
fn preimage_submit_requires_remote_permission_before_backend_call() {
    let platform = Arc::new(StubPlatform {
        remote_permission_denied: true,
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat_with_bulletin(platform.clone(), test_spawner());
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();
    let request = RemotePreimageSubmitRequest::V1(vec![1, 2, 3]);
    let err = futures::executor::block_on(Preimage::submit(&host, &cx, request)).unwrap_err();
    match err {
        CallError::Domain(RemotePreimageSubmitError::V1(v01::PreimageSubmitError::Unknown {
            reason,
        })) => assert_eq!(reason, REMOTE_PERMISSION_DENIED_REASON),
        other => panic!("expected preimage permission denial, got {other:?}"),
    }
    assert!(
        platform
            .sent_rpc
            .lock()
            .expect("rpc list mutex poisoned")
            .is_empty()
    );
}

#[test]
fn chain_broadcast_requires_remote_permission_before_backend_call() {
    let platform = Arc::new(StubPlatform {
        remote_permission_denied: true,
        ..Default::default()
    });
    let host = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    let cx = CallContext::default();
    let request =
        RemoteChainTransactionBroadcastRequest::V1(v01::RemoteChainTransactionBroadcastRequest {
            genesis_hash: vec![0; 32],
            transaction: vec![1, 2, 3],
        });
    let err =
        futures::executor::block_on(Chain::broadcast_transaction(&host, &cx, request)).unwrap_err();
    match err {
        CallError::Domain(RemoteChainTransactionBroadcastError::V1(v01::GenericError {
            reason,
        })) => assert_eq!(reason, REMOTE_PERMISSION_DENIED_REASON),
        other => panic!("expected chain broadcast permission denial, got {other:?}"),
    }
    assert!(platform.sent_rpc.lock().unwrap().is_empty());
}

#[test]
fn preimage_lookup_cache_hit_emits_once_and_stays_open() {
    use futures::FutureExt;

    use crate::host_logic::bulletin::preimage_key;

    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let value = vec![4, 5, 6, 7];
    let key = preimage_key(&value);
    host.services.cache_preimage(key, value.clone());

    let cx = CallContext::default();
    let request =
        RemotePreimageLookupSubscribeRequest::V1(v01::RemotePreimageLookupSubscribeRequest {
            key: key.to_vec(),
        });
    let mut subscription = futures::executor::block_on(host.lookup_subscribe(&cx, request));
    let item = futures::executor::block_on(subscription.next()).expect("preimage item");
    assert_eq!(
        item,
        RemotePreimageLookupSubscribeItem::V1(v01::RemotePreimageLookupSubscribeItem {
            value: Some(value)
        })
    );
    // The subscription stays open (no completion/interrupt frame) after the
    // single cache-hit emission.
    assert!(subscription.next().now_or_never().is_none());
}

#[test]
fn preimage_lookup_forged_host_bytes_downgraded_to_miss() {
    use crate::host_logic::bulletin::preimage_key;

    let value = vec![1, 1, 2, 3, 5, 8];
    let key = preimage_key(&value);

    // Host returns bytes that do not hash to the requested key.
    let forged = Arc::new(StubPlatform {
        preimage_lookup_value: Some(vec![9, 9, 9]),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(forged, test_spawner());
    let cx = CallContext::default();
    let request =
        RemotePreimageLookupSubscribeRequest::V1(v01::RemotePreimageLookupSubscribeRequest {
            key: key.to_vec(),
        });
    let mut subscription = futures::executor::block_on(host.lookup_subscribe(&cx, request));
    let item = futures::executor::block_on(subscription.next()).expect("preimage item");
    assert_eq!(
        item,
        RemotePreimageLookupSubscribeItem::V1(v01::RemotePreimageLookupSubscribeItem {
            value: None
        })
    );

    // Correct bytes pass the integrity check through.
    let genuine = Arc::new(StubPlatform {
        preimage_lookup_value: Some(value.clone()),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(genuine, test_spawner());
    let request =
        RemotePreimageLookupSubscribeRequest::V1(v01::RemotePreimageLookupSubscribeRequest {
            key: key.to_vec(),
        });
    let mut subscription = futures::executor::block_on(host.lookup_subscribe(&cx, request));
    let item = futures::executor::block_on(subscription.next()).expect("preimage item");
    assert_eq!(
        item,
        RemotePreimageLookupSubscribeItem::V1(v01::RemotePreimageLookupSubscribeItem {
            value: Some(value)
        })
    );
}

#[test]
fn theme_subscribe_maps_platform_values() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let mut subscription = futures::executor::block_on(Theme::subscribe(&host, &cx));
    let item = futures::executor::block_on(subscription.next()).expect("theme item");
    assert_eq!(
        item,
        HostThemeSubscribeItem::V1(v01::HostThemeSubscribeItem {
            name: v01::ThemeName::Custom("midnight".to_string()),
            variant: v01::ThemeVariant::Dark,
        })
    );
}

#[test]
fn idle_peer_disconnect_monitor_clears_session_store_and_broadcasts() {
    let session = sso_session_info();
    let platform = Arc::new(StubPlatform {
        rpc_responses: sso_peer_disconnect_monitor_responses(&session),
        ..Default::default()
    });
    let (host_config, product) = runtime_config("myapp.dot");
    let (host, pairing_host) = ProductRuntimeHost::new_pairing_for_tests(
        platform.clone(),
        host_config,
        product,
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    let mut statuses = host.test_session_state().subscribe();
    assert_eq!(
        futures::executor::block_on(statuses.next()).unwrap(),
        HostAccountConnectionStatusSubscribeItem::V1(
            v01::HostAccountConnectionStatusSubscribeItem::Connected
        )
    );

    pairing_host.start_session_supervision_for_current_session();

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
    let disconnected = loop {
        if let Some(item) = statuses.next().now_or_never() {
            break item.expect("status stream ended");
        }
        assert!(
            std::time::Instant::now() < deadline,
            "peer disconnect monitor did not emit Disconnected"
        );
        std::thread::sleep(std::time::Duration::from_millis(5));
    };

    assert!(host.test_session_state().current().is_none());
    assert_eq!(
        *platform
            .session_clears
            .lock()
            .expect("session clear counter mutex poisoned"),
        1
    );
    assert_eq!(
        disconnected,
        HostAccountConnectionStatusSubscribeItem::V1(
            v01::HostAccountConnectionStatusSubscribeItem::Disconnected
        )
    );
}

#[test]
fn legacy_create_transaction_rejects_raw_key_mismatch() {
    let host =
        ProductRuntimeHost::new(stub_platform(), runtime_config("myapp.dot"), test_spawner());
    install_pairing_session(&host, sso_session_info());
    let cx = CallContext::default();
    let request = HostCreateTransactionWithLegacyAccountRequest::V1(v01::LegacyAccountTxPayload {
        signer: [0; 32],
        genesis_hash: [1; 32],
        call_data: vec![0],
        extensions: vec![],
        tx_ext_version: 0,
    });
    let err =
        futures::executor::block_on(host.create_transaction_with_legacy_account(&cx, request))
            .unwrap_err();
    match err {
        CallError::Domain(HostCreateTransactionWithLegacyAccountError::V1(
            v01::HostCreateTransactionError::Unknown { reason },
        )) => assert_eq!(reason, "Account can't be derived from product account id"),
        other => panic!("expected legacy signer mismatch, got {other:?}"),
    }
}

#[test]
fn legacy_create_transaction_accepts_identity_account_then_routes_legacy_request() {
    let session = sso_session_info();
    let identity = session.identity_account_id.unwrap();
    let platform = Arc::new(StubPlatform {
        create_transaction_confirmed: true,
        sso_response_script: Some(sso_success_response_script(
            &session,
            crate::host_logic::sso::messages::RemoteMessage {
                message_id: "wallet-identity-create-tx-1".to_string(),
                data: crate::host_logic::sso::messages::RemoteMessageData::V1(
                    crate::host_logic::sso::messages::v1::RemoteMessage::CreateTransactionResponse(
                        crate::host_logic::sso::messages::Response {
                            responding_to: "identity-create-tx-1".to_string(),
                            payload: Ok(vec![0xca, 0xfe]),
                        },
                    ),
                ),
            },
        )),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    let cx = CallContext::with_request_id("identity-create-tx-1".to_string());
    let request = HostCreateTransactionWithLegacyAccountRequest::V1(v01::LegacyAccountTxPayload {
        signer: identity,
        genesis_hash: [1; 32],
        call_data: vec![0],
        extensions: vec![],
        tx_ext_version: 0,
    });

    let response =
        futures::executor::block_on(host.create_transaction_with_legacy_account(&cx, request))
            .unwrap();

    let HostCreateTransactionWithLegacyAccountResponse::V1(inner) = response;
    assert_eq!(inner.transaction, vec![0xca, 0xfe]);
    let message = submitted_remote_message(&platform, &session);
    let crate::host_logic::sso::messages::RemoteMessageData::V1(
        crate::host_logic::sso::messages::v1::RemoteMessage::CreateTransactionWithLegacyAccountRequest(
            request,
        ),
    ) = message.data
    else {
        panic!("expected identity transaction request");
    };
    let crate::host_logic::sso::messages::CreateTransactionLegacyPayload::V1(payload) =
        request.payload;
    assert_eq!(payload.signer, identity);
}

#[test]
fn legacy_create_transaction_accepts_derived_key_then_returns_sso_response() {
    let session = sso_session_info();
    let signer = test_product_account_public("myapp.dot", 0);
    let platform = Arc::new(StubPlatform {
        create_transaction_confirmed: true,
        sso_response_script: Some(sso_success_response_script(
            &session,
            crate::host_logic::sso::messages::RemoteMessage {
                message_id: "wallet-legacy-create-tx-1".to_string(),
                data: crate::host_logic::sso::messages::RemoteMessageData::V1(
                    crate::host_logic::sso::messages::v1::RemoteMessage::CreateTransactionResponse(
                        crate::host_logic::sso::messages::Response {
                            responding_to: "legacy-create-tx-1".to_string(),
                            payload: Ok(vec![0xca, 0xfe]),
                        },
                    ),
                ),
            },
        )),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    let cx = CallContext::with_request_id("legacy-create-tx-1".to_string());
    let request = HostCreateTransactionWithLegacyAccountRequest::V1(v01::LegacyAccountTxPayload {
        signer,
        genesis_hash: [1; 32],
        call_data: vec![0],
        extensions: vec![],
        tx_ext_version: 0,
    });

    let response =
        futures::executor::block_on(host.create_transaction_with_legacy_account(&cx, request))
            .unwrap();

    let HostCreateTransactionWithLegacyAccountResponse::V1(inner) = response;
    assert_eq!(inner.transaction, vec![0xca, 0xfe]);
    let message = submitted_remote_message(&platform, &session);
    let crate::host_logic::sso::messages::RemoteMessageData::V1(
        crate::host_logic::sso::messages::v1::RemoteMessage::CreateTransactionRequest(request),
    ) = message.data
    else {
        panic!("expected product transaction request");
    };
    let crate::host_logic::sso::messages::CreateTransactionPayload::V1(payload) = request.payload;
    assert_eq!(
        payload.signer,
        v01::ProductAccountId {
            dot_ns_identifier: "myapp.dot".to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        }
    );
}

#[test]
fn resource_allocation_rejects_without_session() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let err = futures::executor::block_on(ResourceAllocation::request(
        &host,
        &cx,
        resource_allocation_request(),
    ))
    .unwrap_err();
    match err {
        CallError::Domain(HostRequestResourceAllocationError::V1(
            v01::ResourceAllocationError::Unknown { reason },
        )) => assert_eq!(reason, "No active session"),
        other => panic!("expected no-session resource allocation error, got {other:?}"),
    }
}

#[test]
fn resource_allocation_rejects_when_user_declines() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();
    let err = futures::executor::block_on(ResourceAllocation::request(
        &host,
        &cx,
        resource_allocation_request(),
    ))
    .unwrap_err();
    match err {
        CallError::Domain(HostRequestResourceAllocationError::V1(
            v01::ResourceAllocationError::Unknown { reason },
        )) => assert_eq!(reason, "User rejected resource allocation"),
        other => panic!("expected user-rejected resource allocation error, got {other:?}"),
    }
}

#[test]
fn resource_allocation_maps_confirmation_failure_to_host_failure() {
    let host = ProductRuntimeHost::new_compat(
        Arc::new(StubPlatform {
            resource_allocation_error: Some("modal failed"),
            ..Default::default()
        }),
        test_spawner(),
    );
    install_pairing_session(&host, session_info());
    let cx = CallContext::default();
    let err = futures::executor::block_on(ResourceAllocation::request(
        &host,
        &cx,
        resource_allocation_request(),
    ))
    .unwrap_err();
    assert!(matches!(err, CallError::HostFailure { reason } if reason.contains("modal failed")));
}

#[test]
fn resource_allocation_respects_a_shorter_call_context_timeout() {
    let session = sso_session_info();
    let message_id = "allocation-timeout";
    let mut rpc_responses = sso_success_responses(
        &session,
        message_id,
        crate::host_logic::sso::messages::RemoteMessage {
            message_id: "wallet-allocation-timeout".to_string(),
            data: crate::host_logic::sso::messages::RemoteMessageData::V1(
                crate::host_logic::sso::messages::v1::RemoteMessage::ResourceAllocationResponse(
                    crate::host_logic::sso::messages::Response {
                        responding_to: message_id.to_string(),
                        payload: Ok(vec![]),
                    },
                ),
            ),
        },
    );
    rpc_responses.truncate(3);
    let platform = Arc::new(StubPlatform {
        resource_allocation_confirmed: true,
        rpc_responses,
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    install_pairing_session(&host, session);
    let mut cx = CallContext::with_request_id(message_id.to_string());
    cx.set_timeout(std::time::Duration::from_millis(1));

    let err = futures::executor::block_on(ResourceAllocation::request(
        &host,
        &cx,
        resource_allocation_request(),
    ))
    .unwrap_err();

    match err {
        CallError::Domain(HostRequestResourceAllocationError::V1(
            v01::ResourceAllocationError::Unknown { reason },
        )) => assert_eq!(
            reason,
            "Account authority request timed out after 1ms for allocation-timeout"
        ),
        other => panic!("expected resource-allocation timeout, got {other:?}"),
    }

    wait_until(
        || recorded_rpc_method_count(&platform.sent_rpc, "statement_unsubscribeStatement") == 2,
        "timed-out resource allocation did not unsubscribe statement streams",
    );
}

#[test]
fn resource_allocation_accepts_confirmation_then_returns_sso_response() {
    let session = sso_session_info();
    let slot_account_key = {
        let mini_secret = schnorrkel::MiniSecretKey::from_bytes(&[12; 32]).unwrap();
        let keypair = mini_secret.expand_to_keypair(schnorrkel::ExpansionMode::Ed25519);
        keypair.secret.to_bytes().to_vec()
    };
    let platform = Arc::new(StubPlatform {
        resource_allocation_confirmed: true,
        sso_response_script: Some(sso_success_response_script(
            &session,
            crate::host_logic::sso::messages::RemoteMessage {
                message_id: "wallet-alloc-1".to_string(),
                data: crate::host_logic::sso::messages::RemoteMessageData::V1(
                    crate::host_logic::sso::messages::v1::RemoteMessage::ResourceAllocationResponse(
                        crate::host_logic::sso::messages::Response {
                            responding_to: "alloc-1".to_string(),
                            payload: Ok(vec![
                                crate::host_logic::sso::messages::SsoAllocationOutcome::Allocated(
                                    crate::host_logic::sso::messages::SsoAllocatedResource::StatementStoreAllowance {
                                        slot_account_key,
                                    },
                                ),
                                crate::host_logic::sso::messages::SsoAllocationOutcome::Rejected,
                                crate::host_logic::sso::messages::SsoAllocationOutcome::NotAvailable,
                            ]),
                        },
                    ),
                ),
            },
        )),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    install_pairing_session(&host, session.clone());
    let cx = CallContext::with_request_id("alloc-1".to_string());
    let response = futures::executor::block_on(ResourceAllocation::request(
        &host,
        &cx,
        resource_allocation_request(),
    ))
    .unwrap();
    let HostRequestResourceAllocationResponse::V1(inner) = response;
    assert_eq!(
        inner.outcomes,
        vec![
            v01::AllocationOutcome::Allocated,
            v01::AllocationOutcome::Rejected,
            v01::AllocationOutcome::NotAvailable,
        ]
    );
    let message = submitted_remote_message(&platform, &session);
    assert!(matches!(
        message.data,
        crate::host_logic::sso::messages::RemoteMessageData::V1(
            crate::host_logic::sso::messages::v1::RemoteMessage::ResourceAllocationRequest(_)
        )
    ));
}

fn auto_signing_test_platform(session: &SessionInfo, request_id: &str) -> Arc<StubPlatform> {
    let root =
        crate::host_logic::product_account::derive_root_keypair_from_entropy(&[0xAB; 16]).unwrap();
    let subtree =
        crate::host_logic::product_account::derive_product_subtree_keypair(&root, "myapp.dot")
            .unwrap();
    Arc::new(StubPlatform {
        resource_allocation_confirmed: true,
        sso_response_script: Some(sso_success_response_script(
            session,
            RemoteMessage {
                message_id: format!("wallet-{request_id}"),
                data: RemoteMessageData::V1(v1::RemoteMessage::ResourceAllocationResponse(
                    crate::host_logic::sso::messages::Response {
                        responding_to: request_id.to_string(),
                        payload: Ok(vec![
                            crate::host_logic::sso::messages::SsoAllocationOutcome::Allocated(
                                crate::host_logic::sso::messages::SsoAllocatedResource::AutoSigning {
                                    product_root_private_key: subtree.secret.to_bytes(),
                                    ring_vrf_domain_entropy:
                                        crate::host_logic::product_account::derive_ring_vrf_domain_entropy(
                                            &[0xAB; 16],
                                            "myapp.dot",
                                        )
                                        .unwrap(),
                                },
                            ),
                        ]),
                    },
                )),
            },
        )),
        ..Default::default()
    })
}

fn request_auto_signing(host: &ProductRuntimeHost, request_id: &str) {
    futures::executor::block_on(ResourceAllocation::request(
        host,
        &CallContext::with_request_id(request_id.to_string()),
        HostRequestResourceAllocationRequest::V1(v01::HostRequestResourceAllocationRequest {
            resources: vec![v01::AllocatableResource::AutoSigning],
        }),
    ))
    .expect("AutoSigning allocation succeeds");
}

fn auto_signing_vrf_request() -> HostAccountSignVrfRequest {
    HostAccountSignVrfRequest::V1(v01::HostAccountSignVrfRequest {
        account: account_id("myapp.dot", 0),
        transcript_label: b"ctx".to_vec(),
        items: vec![v01::VrfTranscriptItem {
            label: b"round".to_vec(),
            value: vec![7],
        }],
    })
}

#[test]
fn auto_signing_allocation_persists_and_serves_vrf_without_sso() {
    let session = sso_session_info();
    let root =
        crate::host_logic::product_account::derive_root_keypair_from_entropy(&[0xAB; 16]).unwrap();
    let subtree =
        crate::host_logic::product_account::derive_product_subtree_keypair(&root, "myapp.dot")
            .unwrap();
    let product_root_private_key = subtree.secret.to_bytes();
    let platform = Arc::new(StubPlatform {
        resource_allocation_confirmed: true,
        sso_response_script: Some(sso_success_response_script(
            &session,
            RemoteMessage {
                message_id: "wallet-auto-1".to_string(),
                data: RemoteMessageData::V1(v1::RemoteMessage::ResourceAllocationResponse(
                    crate::host_logic::sso::messages::Response {
                        responding_to: "auto-1".to_string(),
                        payload: Ok(vec![
                            crate::host_logic::sso::messages::SsoAllocationOutcome::Allocated(
                                crate::host_logic::sso::messages::SsoAllocatedResource::AutoSigning {
                                    product_root_private_key,
                                    ring_vrf_domain_entropy:
                                        crate::host_logic::product_account::derive_ring_vrf_domain_entropy(
                                            &[0xAB; 16],
                                            "myapp.dot",
                                        )
                                        .unwrap(),
                                },
                            ),
                        ]),
                    },
                )),
            },
        )),
        ..Default::default()
    });
    let host = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    let allocation =
        HostRequestResourceAllocationRequest::V1(v01::HostRequestResourceAllocationRequest {
            resources: vec![v01::AllocatableResource::AutoSigning],
        });
    futures::executor::block_on(ResourceAllocation::request(
        &host,
        &CallContext::with_request_id("auto-1".to_string()),
        allocation,
    ))
    .expect("AutoSigning allocation succeeds");

    let restored = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    restored.test_session_state().set_session(session);
    let request = v01::HostAccountSignVrfRequest {
        account: account_id("myapp.dot", 0),
        transcript_label: b"ctx".to_vec(),
        items: vec![v01::VrfTranscriptItem {
            label: b"round".to_vec(),
            value: vec![7],
        }],
    };
    let response = futures::executor::block_on(restored.sign_vrf(
        &CallContext::default(),
        HostAccountSignVrfRequest::V1(request),
    ))
    .expect("persisted AutoSigning key signs locally");
    let HostAccountSignVrfResponse::V1(signature) = response;
    assert!(
        platform
            .sign_vrf_reviews
            .lock()
            .expect("VRF signing review list mutex poisoned")
            .is_empty()
    );

    let keypair = crate::host_logic::product_account::derive_product_keypair(
        &root,
        "myapp.dot",
        index_bytes(0),
    )
    .unwrap();
    let mut transcript = merlin::Transcript::new(b"ctx");
    transcript.append_message(b"round", &[7]);
    let pre_output = schnorrkel::vrf::VRFPreOut::from_bytes(&signature.pre_output).unwrap();
    let proof = schnorrkel::vrf::VRFProof::from_bytes(&signature.proof).unwrap();
    keypair
        .public
        .vrf_verify(transcript, &pre_output, &proof)
        .expect("local AutoSigning VRF verifies");
}

#[test]
fn ring_vrf_sign_reports_not_connected_before_foreign_key_policy() {
    let host = ProductRuntimeHost::new(
        Arc::new(StubPlatform::default()),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    let request = HostAccountRingVrfSignRequest::V1(v01::HostAccountRingVrfSignRequest {
        key_handle: account_id("other.dot", 0),
        message: b"not connected".to_vec(),
    });

    let error = futures::executor::block_on(host.ring_vrf_sign(&CallContext::default(), request))
        .unwrap_err();

    assert!(matches!(
        error,
        CallError::Domain(HostAccountRingVrfSignError::V1(
            v01::HostAccountRingVrfSignError::NotConnected
        ))
    ));
}

#[test]
fn auto_signing_ring_vrf_requires_registration_and_signs_locally() {
    use verifiable::GenerateVerifiable;
    use verifiable::ring::bandersnatch::BandersnatchVrfVerifiable;

    let session = sso_session_info();
    let platform = Arc::new(StubPlatform::default());
    let (host, pairing_host) = ProductRuntimeHost::new_pairing_for_tests(
        platform.clone(),
        ProductRuntimeHost::compat_host_config(),
        ProductContext::new("myapp.dot".to_string()).unwrap(),
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());

    let root =
        crate::host_logic::product_account::derive_root_keypair_from_entropy(&[0xAB; 16]).unwrap();
    let subtree =
        crate::host_logic::product_account::derive_product_subtree_keypair(&root, "myapp.dot")
            .unwrap();
    let domain = crate::host_logic::product_account::derive_ring_vrf_domain_entropy(
        &[0xAB; 16],
        "myapp.dot",
    )
    .unwrap();
    futures::executor::block_on(pairing_host.remember_auto_signing_key_for_tests(
        &session,
        pairing_host.current_session_lifecycle_epoch(),
        "myapp.dot",
        subtree.public.to_bytes(),
        subtree.secret.to_bytes(),
        domain,
    ))
    .unwrap();

    let handle = account_id("myapp.dot", 7);
    let request = HostAccountRingVrfSignRequest::V1(v01::HostAccountRingVrfSignRequest {
        key_handle: handle.clone(),
        message: b"registered keys only".to_vec(),
    });
    let error = futures::executor::block_on(host.ring_vrf_sign(&CallContext::default(), request))
        .unwrap_err();
    assert!(matches!(
        error,
        CallError::Domain(HostAccountRingVrfSignError::V1(
            v01::HostAccountRingVrfSignError::KeyNotRegistered
        ))
    ));

    let ring = ring_location_fixture();
    let entropy = crate::host_logic::product_account::derive_ring_vrf_entropy_from_domain(
        &domain,
        &handle.derivation_index,
    );
    let public_key = crate::runtime::signing_host::ring_vrf::member_from_entropy(&entropy).unwrap();
    futures::executor::block_on(pairing_host.register_ring_vrf_key_for_tests(
        &session,
        handle.clone(),
        ring,
        public_key,
    ))
    .unwrap();

    let message = b"registered keys only".to_vec();
    let response = futures::executor::block_on(host.ring_vrf_sign(
        &CallContext::default(),
        HostAccountRingVrfSignRequest::V1(v01::HostAccountRingVrfSignRequest {
            key_handle: handle,
            message: message.clone(),
        }),
    ))
    .unwrap();
    let HostAccountRingVrfSignResponse::V1(signature) = response;
    let signature: [u8; 64] = signature
        .try_into()
        .expect("fixed-width ring-VRF signature");
    assert!(BandersnatchVrfVerifiable::verify_signature(
        &signature,
        &message,
        &public_key
    ));
    assert!(
        platform
            .sent_rpc
            .lock()
            .expect("sent RPC mutex poisoned")
            .is_empty(),
        "registered AutoSigning ring-VRF use stays local"
    );

    let mismatched_handle = account_id("myapp.dot", 8);
    futures::executor::block_on(pairing_host.register_ring_vrf_key_for_tests(
        &session,
        mismatched_handle.clone(),
        ring_location_fixture(),
        [0xFF; 32],
    ))
    .unwrap();
    let error = futures::executor::block_on(host.ring_vrf_sign(
        &CallContext::default(),
        HostAccountRingVrfSignRequest::V1(v01::HostAccountRingVrfSignRequest {
            key_handle: mismatched_handle,
            message: b"reject mismatched registry state".to_vec(),
        }),
    ))
    .unwrap_err();
    assert!(matches!(
        error,
        CallError::Domain(HostAccountRingVrfSignError::V1(
            v01::HostAccountRingVrfSignError::Unknown { reason }
        )) if reason.contains("does not match the AutoSigning capability")
    ));
}

#[test]
fn auto_signing_rejects_persisted_key_for_unexpected_product_subtree() {
    let session = sso_session_info();
    let platform = auto_signing_test_platform(&session, "auto-tamper");
    let host = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    request_auto_signing(&host, "auto-tamper");

    let expected_subtree = test_product_subtree("myapp.dot");
    let storage_key = core_storage_test_key(CoreStorageKey::AutoSigningKeys);
    {
        let mut storage = platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned");
        let blob = storage
            .get_mut(&storage_key)
            .expect("scoped AutoSigning capability persisted");
        let expected_offset = blob
            .windows(expected_subtree.len())
            .position(|window| window == expected_subtree)
            .expect("persisted expected subtree is present");
        blob[expected_offset] ^= 0x01;
    }

    let restored = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&restored, session);
    let err = futures::executor::block_on(
        restored.sign_vrf(&CallContext::default(), auto_signing_vrf_request()),
    )
    .unwrap_err();

    assert!(matches!(
        err,
        CallError::Domain(HostAccountSignVrfError::V1(
            v01::HostAccountSignVrfError::Unknown { reason }
        )) if reason == "AutoSigning capability is not for the current product subtree"
    ));
    assert!(
        !platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .contains_key(&storage_key)
    );
}

#[test]
fn auto_signing_logout_reset_clears_cached_and_persisted_capability() {
    let session = sso_session_info();
    let platform = auto_signing_test_platform(&session, "auto-logout");
    let (host_config, product) = runtime_config("myapp.dot");
    let (host, pairing_host) = ProductRuntimeHost::new_pairing_for_tests(
        platform.clone(),
        host_config,
        product,
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    request_auto_signing(&host, "auto-logout");
    assert!(
        platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .contains_key(&core_storage_test_key(CoreStorageKey::AutoSigningKeys))
    );

    futures::executor::block_on(pairing_host.logout_and_reset_pairing()).unwrap();

    assert!(
        !platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .contains_key(&core_storage_test_key(CoreStorageKey::AutoSigningKeys))
    );
    assert!(
        !futures::executor::block_on(
            pairing_host.has_auto_signing_key_for_tests(&session, "myapp.dot")
        )
        .expect("AutoSigning storage remains readable"),
        "logout must evict the in-memory AutoSigning capability"
    );
}

#[test]
fn stale_secret_allocations_cannot_persist_after_reset_and_same_owner_reactivation() {
    let session = sso_session_info();
    let platform = Arc::new(StubPlatform::default());
    let (host_config, product) = runtime_config("myapp.dot");
    let (host, pairing_host) = ProductRuntimeHost::new_pairing_for_tests(
        platform.clone(),
        host_config,
        product,
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    let stale_epoch = pairing_host.current_session_lifecycle_epoch();
    let root =
        crate::host_logic::product_account::derive_root_keypair_from_entropy(&[0xAB; 16]).unwrap();
    let subtree =
        crate::host_logic::product_account::derive_product_subtree_keypair(&root, "myapp.dot")
            .unwrap();

    futures::executor::block_on(pairing_host.logout_and_reset_pairing()).unwrap();
    futures::executor::block_on(pairing_host.set_connected_session_for_tests(session.clone()));
    let auto_signing_error =
        futures::executor::block_on(pairing_host.remember_auto_signing_key_for_tests(
            &session,
            stale_epoch,
            "myapp.dot",
            subtree.public.to_bytes(),
            subtree.secret.to_bytes(),
            [0x42; 32],
        ))
        .expect_err("the old AutoSigning allocation completion must be rejected");
    let statement_store_result =
        futures::executor::block_on(pairing_host.cache_statement_store_allowance_key(
            &session,
            stale_epoch,
            "myapp.dot",
            subtree.secret.to_bytes().to_vec(),
        ));
    let Err(statement_store_error) = statement_store_result else {
        panic!("the old statement-store allocation completion must be rejected");
    };
    let bulletin_result = futures::executor::block_on(pairing_host.cache_bulletin_allowance_key(
        &session,
        stale_epoch,
        "myapp.dot",
        subtree.secret.to_bytes().to_vec(),
    ));
    let Err(bulletin_error) = bulletin_result else {
        panic!("the old Bulletin allocation completion must be rejected");
    };

    assert!(matches!(auto_signing_error, AuthorityError::Disconnected));
    assert!(matches!(
        statement_store_error,
        AuthorityError::Disconnected
    ));
    assert!(matches!(bulletin_error, AuthorityError::Disconnected));
    assert!(
        !platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .contains_key(&core_storage_test_key(CoreStorageKey::AutoSigningKeys)),
        "the stale allocation must not restore durable AutoSigning authority"
    );
    assert!(
        platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .is_empty(),
        "stale allowance completions must not restore durable slot secrets"
    );
    assert!(
        !futures::executor::block_on(
            pairing_host.has_auto_signing_key_for_tests(&session, "myapp.dot")
        )
        .expect("AutoSigning storage remains readable"),
        "the stale allocation must not restore cached AutoSigning authority"
    );
}

#[test]
fn product_clear_preserves_other_capabilities_and_fences_stale_work() {
    let session = sso_session_info();
    let platform = Arc::new(StubPlatform::default());
    let (host_config, product) = runtime_config("myapp.dot");
    let (host, pairing_host) = ProductRuntimeHost::new_pairing_for_tests(
        platform.clone(),
        host_config,
        product,
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    cache_test_product_subtree(&host, &session, "other.dot");
    let stale_epoch = pairing_host.current_session_lifecycle_epoch();
    let root =
        crate::host_logic::product_account::derive_root_keypair_from_entropy(&[0xAB; 16]).unwrap();
    let first =
        crate::host_logic::product_account::derive_product_subtree_keypair(&root, "myapp.dot")
            .unwrap();
    let other =
        crate::host_logic::product_account::derive_product_subtree_keypair(&root, "other.dot")
            .unwrap();

    for (product_id, subtree) in [("myapp.dot", &first), ("other.dot", &other)] {
        futures::executor::block_on(pairing_host.remember_auto_signing_key_for_tests(
            &session,
            stale_epoch,
            product_id,
            subtree.public.to_bytes(),
            subtree.secret.to_bytes(),
            [0x42; 32],
        ))
        .unwrap();
        futures::executor::block_on(pairing_host.cache_statement_store_allowance_key(
            &session,
            stale_epoch,
            product_id,
            subtree.secret.to_bytes().to_vec(),
        ))
        .unwrap();
        futures::executor::block_on(pairing_host.cache_bulletin_allowance_key(
            &session,
            stale_epoch,
            product_id,
            subtree.secret.to_bytes().to_vec(),
        ))
        .unwrap();
    }

    futures::executor::block_on(pairing_host.clear_product_state("myapp.dot")).unwrap();
    let current_epoch = pairing_host.current_session_lifecycle_epoch();
    assert_ne!(current_epoch, stale_epoch);
    assert_eq!(
        pairing_host.capability_cache_sizes_for_tests(),
        (1, 1, 1, 1)
    );
    assert!(
        !futures::executor::block_on(
            pairing_host.has_auto_signing_key_for_tests(&session, "myapp.dot")
        )
        .unwrap()
    );
    assert!(
        futures::executor::block_on(
            pairing_host.has_auto_signing_key_for_tests(&session, "other.dot")
        )
        .unwrap()
    );
    assert!(
        futures::executor::block_on(pairing_host.cached_statement_store_allowance_key(
            &session,
            current_epoch,
            "myapp.dot",
        ))
        .unwrap()
        .is_none()
    );
    assert!(
        futures::executor::block_on(pairing_host.cached_statement_store_allowance_key(
            &session,
            current_epoch,
            "other.dot",
        ))
        .unwrap()
        .is_some()
    );
    assert!(
        futures::executor::block_on(pairing_host.cached_bulletin_allowance_key(
            &session,
            current_epoch,
            "myapp.dot",
        ))
        .unwrap()
        .is_none()
    );
    assert!(
        futures::executor::block_on(pairing_host.cached_bulletin_allowance_key(
            &session,
            current_epoch,
            "other.dot",
        ))
        .unwrap()
        .is_some()
    );

    assert!(matches!(
        futures::executor::block_on(pairing_host.remember_auto_signing_key_for_tests(
            &session,
            stale_epoch,
            "myapp.dot",
            first.public.to_bytes(),
            first.secret.to_bytes(),
            [0x42; 32],
        )),
        Err(AuthorityError::Disconnected)
    ));
    assert!(matches!(
        futures::executor::block_on(pairing_host.cache_statement_store_allowance_key(
            &session,
            stale_epoch,
            "myapp.dot",
            first.secret.to_bytes().to_vec(),
        )),
        Err(AuthorityError::Disconnected)
    ));
    assert_eq!(
        pairing_host.capability_cache_sizes_for_tests(),
        (1, 1, 1, 1)
    );
    assert_eq!(
        platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .len(),
        2,
        "the aggregate AutoSigning and active-session allowance blobs remain for other.dot"
    );
}

#[test]
fn reset_session_state_clears_all_capabilities_without_peer_traffic() {
    let session = sso_session_info();
    let platform = Arc::new(StubPlatform::default());
    let (host_config, product) = runtime_config("myapp.dot");
    let (host, pairing_host) = ProductRuntimeHost::new_pairing_for_tests(
        platform.clone(),
        host_config,
        product,
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    let lifecycle_epoch = pairing_host.current_session_lifecycle_epoch();
    let root =
        crate::host_logic::product_account::derive_root_keypair_from_entropy(&[0xAB; 16]).unwrap();
    let subtree =
        crate::host_logic::product_account::derive_product_subtree_keypair(&root, "myapp.dot")
            .unwrap();
    futures::executor::block_on(pairing_host.remember_auto_signing_key_for_tests(
        &session,
        lifecycle_epoch,
        "myapp.dot",
        subtree.public.to_bytes(),
        subtree.secret.to_bytes(),
        [0x42; 32],
    ))
    .unwrap();
    futures::executor::block_on(pairing_host.cache_statement_store_allowance_key(
        &session,
        lifecycle_epoch,
        "myapp.dot",
        subtree.secret.to_bytes().to_vec(),
    ))
    .unwrap();
    futures::executor::block_on(pairing_host.cache_bulletin_allowance_key(
        &session,
        lifecycle_epoch,
        "myapp.dot",
        subtree.secret.to_bytes().to_vec(),
    ))
    .unwrap();
    assert_eq!(
        pairing_host.capability_cache_sizes_for_tests(),
        (1, 1, 1, 1)
    );

    futures::executor::block_on(pairing_host.reset_session_state());

    assert!(pairing_host.session_state().current().is_none());
    assert_eq!(
        pairing_host.capability_cache_sizes_for_tests(),
        (0, 0, 0, 0)
    );
    assert!(
        platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .is_empty()
    );
    assert!(
        platform
            .sent_rpc
            .lock()
            .expect("sent RPC mutex poisoned")
            .is_empty(),
        "canonical reset must not submit a duplicate peer-disconnect statement"
    );
}

#[test]
fn identity_replacement_clears_all_stale_wallet_capabilities() {
    let session = sso_session_info();
    let platform = auto_signing_test_platform(&session, "auto-replace");
    let (host_config, product) = runtime_config("myapp.dot");
    let (host, pairing_host) = ProductRuntimeHost::new_pairing_for_tests(
        platform.clone(),
        host_config,
        product,
        test_spawner(),
    );
    install_pairing_session(&host, session.clone());
    request_auto_signing(&host, "auto-replace");
    let lifecycle_epoch = pairing_host.current_session_lifecycle_epoch();
    let root =
        crate::host_logic::product_account::derive_root_keypair_from_entropy(&[0xAB; 16]).unwrap();
    let subtree =
        crate::host_logic::product_account::derive_product_subtree_keypair(&root, "myapp.dot")
            .unwrap();
    futures::executor::block_on(pairing_host.cache_statement_store_allowance_key(
        &session,
        lifecycle_epoch,
        "myapp.dot",
        subtree.secret.to_bytes().to_vec(),
    ))
    .unwrap();
    futures::executor::block_on(pairing_host.cache_bulletin_allowance_key(
        &session,
        lifecycle_epoch,
        "myapp.dot",
        subtree.secret.to_bytes().to_vec(),
    ))
    .unwrap();

    let mut replacement = session;
    replacement.public_key = [0x44; 32];
    replacement
        .sso
        .as_mut()
        .expect("fixture has SSO identity")
        .identity_account_id = [0x55; 32];
    futures::executor::block_on(pairing_host.set_connected_session_for_tests(replacement.clone()));

    assert_eq!(
        host.test_session_state().current(),
        Some(replacement.clone())
    );
    assert!(
        !platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .contains_key(&core_storage_test_key(CoreStorageKey::AutoSigningKeys))
    );
    assert!(
        platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .is_empty(),
        "a replacement wallet must not leave the prior session's durable allowance secrets"
    );
    assert!(
        !futures::executor::block_on(
            pairing_host.has_auto_signing_key_for_tests(&replacement, "myapp.dot")
        )
        .expect("AutoSigning storage remains readable"),
        "a newly paired wallet must not reuse the previous wallet's cached capability"
    );
}

#[test]
fn auto_signing_restored_different_wallet_rejects_persisted_capability() {
    let session = sso_session_info();
    let platform = auto_signing_test_platform(&session, "auto-other-wallet");
    let original = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&original, session.clone());
    request_auto_signing(&original, "auto-other-wallet");

    let mut replacement = session;
    replacement.public_key = [0x66; 32];
    replacement
        .sso
        .as_mut()
        .expect("fixture has SSO identity")
        .identity_account_id = [0x77; 32];
    let (host_config, product) = runtime_config("myapp.dot");
    let (restored, pairing_host) = ProductRuntimeHost::new_pairing_for_tests(
        platform.clone(),
        host_config,
        product,
        test_spawner(),
    );
    install_pairing_session(&restored, replacement.clone());

    assert!(
        !futures::executor::block_on(
            pairing_host.has_auto_signing_key_for_tests(&replacement, "myapp.dot")
        )
        .expect("AutoSigning storage remains readable"),
        "a different restored wallet must not use a prior wallet's capability"
    );
    assert!(
        !platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .contains_key(&core_storage_test_key(CoreStorageKey::AutoSigningKeys))
    );
}

#[test]
fn auto_signing_rejects_and_erases_legacy_unscoped_secret() {
    let session = sso_session_info();
    let root =
        crate::host_logic::product_account::derive_root_keypair_from_entropy(&[0xAB; 16]).unwrap();
    let subtree =
        crate::host_logic::product_account::derive_product_subtree_keypair(&root, "myapp.dot")
            .unwrap();
    let platform = Arc::new(StubPlatform::default());
    let legacy_key = CoreStorageKey::AutoSigningKey {
        product_id: "myapp.dot".to_string(),
    };
    platform
        .local_storage
        .lock()
        .expect("local storage mutex poisoned")
        .insert(
            core_storage_test_key(legacy_key.clone()),
            subtree.secret.to_bytes().to_vec(),
        );
    let host = ProductRuntimeHost::new(
        platform.clone(),
        runtime_config("myapp.dot"),
        test_spawner(),
    );
    install_pairing_session(&host, session);

    let err = futures::executor::block_on(
        host.sign_vrf(&CallContext::default(), auto_signing_vrf_request()),
    )
    .unwrap_err();

    assert!(matches!(
        err,
        CallError::Domain(HostAccountSignVrfError::V1(
            v01::HostAccountSignVrfError::Unknown { reason }
        )) if reason == "legacy unscoped AutoSigning capability was rejected"
    ));
    assert!(
        !platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .contains_key(&core_storage_test_key(legacy_key))
    );
}

#[test]
fn external_session_activation_is_memory_only_and_rejects_trailing_bytes() {
    let platform = Arc::new(StubPlatform::default());
    let (host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());
    let session = sso_session_info();
    let blob = crate::host_logic::session::encode_persisted_session(&session);

    futures::executor::block_on(pairing_host.activate_external_session(&blob))
        .expect("valid external session activates");

    assert_eq!(host.test_session_state().current(), Some(session.clone()));
    assert!(
        platform
            .session_writes
            .lock()
            .expect("session write list mutex poisoned")
            .is_empty(),
        "external activation must not copy the blob into core storage"
    );

    let invalid = futures::executor::block_on(pairing_host.activate_external_session(&[0xff]))
        .expect_err("invalid bytes are rejected");
    assert!(invalid.starts_with("invalid session blob:"));

    let mut trailing = blob;
    trailing.push(0);
    let error = futures::executor::block_on(pairing_host.activate_external_session(&trailing))
        .expect_err("trailing bytes are rejected");
    assert_eq!(error, "invalid session blob: trailing bytes");
    assert_eq!(
        host.test_session_state().current(),
        Some(session),
        "invalid replacement preserves the active external session"
    );
}

#[test]
fn external_session_activation_reports_its_outcome_when_the_blob_is_corrupt() {
    let platform = Arc::new(StubPlatform::default());
    let (_host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());

    futures::executor::block_on(pairing_host.activate_external_session(&[0xff]))
        .expect_err("invalid bytes are rejected");

    // The decode fails before any transition can run, so without an
    // explicit announcement a host that holds its own session and boots on
    // a corrupt blob would hear nothing at all.
    assert_eq!(
        *platform
            .auth_states
            .lock()
            .expect("auth state list mutex poisoned"),
        vec![AuthState::Disconnected],
        "an activation that failed must still tell the host where it stands"
    );
}

#[test]
fn resetting_session_state_reports_its_outcome_when_nothing_was_active() {
    let platform = Arc::new(StubPlatform::default());
    let (_host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());

    futures::executor::block_on(pairing_host.reset_session_state());

    // Clearing an already-signed-out state changes nothing, so without an
    // explicit announcement this is the silent case a host cannot tell
    // apart from having had no answer yet.
    assert_eq!(
        *platform
            .auth_states
            .lock()
            .expect("auth state list mutex poisoned"),
        vec![AuthState::Disconnected],
        "a reset must still tell the host where it stands"
    );
}

#[test]
fn external_session_activation_replaces_and_fences_the_previous_session() {
    let (host, pairing_host) = ProductRuntimeHost::new_compat_with_pairing(
        Arc::new(StubPlatform::default()),
        test_spawner(),
    );
    let first = sso_session_info();
    let mut replacement = first.clone();
    replacement.public_key = [0x44; 32];
    replacement.identity_account_id = Some([0x55; 32]);
    replacement
        .sso
        .as_mut()
        .expect("fixture has SSO")
        .identity_account_id = [0x55; 32];

    futures::executor::block_on(pairing_host.activate_external_session(
        &crate::host_logic::session::encode_persisted_session(&first),
    ))
    .expect("first external session activates");
    futures::executor::block_on(pairing_host.activate_external_session(
        &crate::host_logic::session::encode_persisted_session(&replacement),
    ))
    .expect("replacement external session activates");

    assert_eq!(host.test_session_state().current(), Some(replacement));
}

#[test]
fn store_notification_during_external_activation_restores_persisted_session() {
    let persisted = sso_session_info();
    let platform = Arc::new(StubPlatform {
        session_blob: Some(crate::host_logic::session::encode_persisted_session(
            &persisted,
        )),
        ..Default::default()
    });
    let (host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform, test_spawner());
    pairing_host
        .clone()
        .start_session_store_sync_for_tests(test_spawner());
    wait_until(
        || host.test_session_state().current() == Some(persisted.clone()),
        "initial persisted session was not restored",
    );

    let mut stale_external = persisted.clone();
    stale_external.public_key = [0x44; 32];
    let stale_blob = crate::host_logic::session::encode_persisted_session(&stale_external);
    let (activation_entered, resume_activation) =
        pairing_host.pause_external_session_activation_for_tests();
    let activation = std::thread::spawn({
        let pairing_host = pairing_host.clone();
        move || futures::executor::block_on(pairing_host.activate_external_session(&stale_blob))
    });
    futures::executor::block_on(activation_entered)
        .expect("external activation reached the installation fence");

    pairing_host.notify_session_store_changed();
    resume_activation
        .send(())
        .expect("external activation remains in flight");
    activation
        .join()
        .expect("external activation thread panicked")
        .expect("superseded external activation completes");

    wait_until(
        || host.test_session_state().current() == Some(persisted.clone()),
        "store reconciliation did not preserve the persisted replacement",
    );
    assert_eq!(host.test_session_state().current(), Some(persisted));
}

#[test]
fn disconnect_during_external_activation_prevents_stale_reinstallation() {
    let (host, pairing_host) = ProductRuntimeHost::new_compat_with_pairing(
        Arc::new(StubPlatform::default()),
        test_spawner(),
    );
    let stale_blob = crate::host_logic::session::encode_persisted_session(&sso_session_info());
    let (activation_entered, resume_activation) =
        pairing_host.pause_external_session_activation_for_tests();
    let activation = std::thread::spawn({
        let pairing_host = pairing_host.clone();
        move || futures::executor::block_on(pairing_host.activate_external_session(&stale_blob))
    });
    futures::executor::block_on(activation_entered)
        .expect("external activation reached the installation fence");

    futures::executor::block_on(host.disconnect());
    resume_activation
        .send(())
        .expect("external activation remains in flight");
    activation
        .join()
        .expect("external activation thread panicked")
        .expect("superseded external activation completes");

    assert!(
        host.test_session_state().current().is_none(),
        "disconnect must win over the earlier external activation"
    );
}

#[test]
fn stored_session_activation_resolves_after_connected_installation() {
    let stored = sso_session_info();
    let platform = Arc::new(StubPlatform {
        session_blob: Some(crate::host_logic::session::encode_persisted_session(
            &stored,
        )),
        ..Default::default()
    });
    let (host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());

    futures::executor::block_on(pairing_host.activate_stored_session())
        .expect("valid stored session activates");

    assert_eq!(host.test_session_state().current(), Some(stored.clone()));
    assert_eq!(
        *platform
            .auth_states
            .lock()
            .expect("auth state list mutex poisoned"),
        vec![AuthState::Connected(connected_session_ui_info(&stored))]
    );
}

#[test]
fn stored_session_activation_rejects_invalid_blob_and_disconnects() {
    let session_clears = Arc::new(Mutex::new(0));
    let platform = Arc::new(StubPlatform {
        session_blob: Some(vec![0xff]),
        session_clears: session_clears.clone(),
        ..Default::default()
    });
    let (host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform, test_spawner());
    install_pairing_session(&host, sso_session_info());

    let error = futures::executor::block_on(pairing_host.activate_stored_session())
        .expect_err("invalid stored session is rejected");

    assert!(error.starts_with("invalid stored auth session:"));
    assert!(host.test_session_state().current().is_none());
    assert_eq!(
        *session_clears
            .lock()
            .expect("session clear counter mutex poisoned"),
        1
    );
}

/// An untagged blob restores and the slot is rewritten in the written form, so
/// a host upgrades its stored session by activating once rather than by pairing
/// again. `SessionInfo::encode` is the untagged eight-field layout; the canary in
/// `host_logic::session` is what keeps that true.
#[test]
fn activating_an_untagged_stored_session_restores_it_and_rewrites_the_slot() {
    let stored = sso_session_info();
    let untagged = stored.encode();
    let platform = Arc::new(StubPlatform {
        session_blob: Some(untagged.clone()),
        ..Default::default()
    });
    let (host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());

    futures::executor::block_on(pairing_host.activate_stored_session())
        .expect("an untagged stored session activates");

    assert_eq!(host.test_session_state().current(), Some(stored.clone()));
    let written = crate::host_logic::session::encode_persisted_session(&stored);
    assert_ne!(
        untagged, written,
        "the fixture must not already be in the written form, or this proves nothing"
    );
    assert_eq!(
        platform
            .session_writes
            .lock()
            .expect("session write list mutex poisoned")
            .last(),
        Some(&written),
        "the slot still holds the untagged blob, so it would be re-read on every start"
    );
}

#[test]
fn session_store_sync_restores_valid_blob_from_tick() {
    let stored = sso_session_info();
    let platform = Arc::new(StubPlatform {
        session_blob: Some(crate::host_logic::session::encode_persisted_session(
            &stored,
        )),
        ..Default::default()
    });
    let (host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());

    pairing_host
        .clone()
        .start_session_store_sync_for_tests(test_spawner());
    wait_until(
        || host.test_session_state().current() == Some(stored.clone()),
        "session store sync did not restore valid blob",
    );

    assert_eq!(host.test_session_state().current(), Some(stored.clone()));
    let expected_auth_states = vec![AuthState::Connected(connected_session_ui_info(&stored))];
    wait_until(
        || {
            *platform
                .auth_states
                .lock()
                .expect("auth state list mutex poisoned")
                == expected_auth_states
        },
        "session store sync did not broadcast connected auth state",
    );
    assert_eq!(
        *platform
            .auth_states
            .lock()
            .expect("auth state list mutex poisoned"),
        expected_auth_states
    );
}

#[test]
fn session_store_sync_announces_a_signed_out_boot() {
    let platform = Arc::new(StubPlatform::default());
    let (_host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());

    pairing_host
        .clone()
        .start_session_store_sync_for_tests(test_spawner());

    wait_until(
        || {
            !platform
                .auth_states
                .lock()
                .expect("auth state list mutex poisoned")
                .is_empty()
        },
        "boot reconcile did not report the signed-out state",
    );
    assert_eq!(
        *platform
            .auth_states
            .lock()
            .expect("auth state list mutex poisoned"),
        vec![AuthState::Disconnected]
    );
}

#[test]
fn session_store_sync_announces_a_restored_boot_once() {
    let stored = sso_session_info();
    let platform = Arc::new(StubPlatform {
        session_blob: Some(crate::host_logic::session::encode_persisted_session(
            &stored,
        )),
        ..Default::default()
    });
    let (_host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());

    pairing_host
        .clone()
        .start_session_store_sync_for_tests(test_spawner());

    wait_until(
        || {
            !platform
                .auth_states
                .lock()
                .expect("auth state list mutex poisoned")
                .is_empty()
        },
        "boot reconcile did not report the restored session",
    );
    futures::executor::block_on(pairing_host.activate_stored_session())
        .expect("valid stored session activates");
    assert_eq!(
        *platform
            .auth_states
            .lock()
            .expect("auth state list mutex poisoned"),
        vec![AuthState::Connected(connected_session_ui_info(&stored))]
    );
}

#[test]
fn session_store_sync_stays_silent_on_an_unchanged_tick() {
    let stored = sso_session_info();
    let platform = Arc::new(StubPlatform {
        session_blob: Some(crate::host_logic::session::encode_persisted_session(
            &stored,
        )),
        ..Default::default()
    });
    let (_host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());

    pairing_host
        .clone()
        .start_session_store_sync_for_tests(test_spawner());
    wait_until(
        || {
            !platform
                .auth_states
                .lock()
                .expect("auth state list mutex poisoned")
                .is_empty()
        },
        "boot reconcile did not report the restored session",
    );

    pairing_host.notify_session_store_changed();
    wait_until(
        || pairing_host.session_store_change_ticks_for_tests() == 1,
        "session store sync did not process the change tick",
    );

    // The store still holds the same session, so the tick is not a
    // transition and must not repeat the opening state.
    assert_eq!(
        *platform
            .auth_states
            .lock()
            .expect("auth state list mutex poisoned"),
        vec![AuthState::Connected(connected_session_ui_info(&stored))]
    );
}

#[test]
fn session_store_sync_replaces_valid_blob_and_broadcasts_connected() {
    let mut replacement = sso_session_info();
    replacement.public_key = [0x44; 32];
    let (host, pairing_host) = ProductRuntimeHost::new_compat_with_pairing(
        Arc::new(StubPlatform {
            session_blob: Some(crate::host_logic::session::encode_persisted_session(
                &replacement,
            )),
            ..Default::default()
        }),
        test_spawner(),
    );
    install_pairing_session(&host, sso_session_info());
    let mut statuses = host.test_session_state().subscribe();
    let _ = futures::executor::block_on(statuses.next());

    pairing_host
        .clone()
        .start_session_store_sync_for_tests(test_spawner());

    assert_eq!(
        futures::executor::block_on(statuses.next()).unwrap(),
        HostAccountConnectionStatusSubscribeItem::V1(
            v01::HostAccountConnectionStatusSubscribeItem::Connected
        )
    );
    assert_eq!(host.test_session_state().current(), Some(replacement));
}

#[test]
fn session_store_sync_clears_invalid_blob() {
    let platform = Arc::new(StubPlatform {
        session_blob: Some(vec![0xff]),
        ..Default::default()
    });
    let (host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());
    install_pairing_session(&host, sso_session_info());

    pairing_host
        .clone()
        .start_session_store_sync_for_tests(test_spawner());
    wait_until(
        || host.test_session_state().current().is_none(),
        "session store sync did not clear invalid blob",
    );

    assert!(host.test_session_state().current().is_none());
    // `set_session` bypasses the auth state cell, so the clear is not a
    // transition; the boot tick's announcement is the only emission.
    wait_until(
        || {
            !platform
                .auth_states
                .lock()
                .expect("auth state list mutex poisoned")
                .is_empty()
        },
        "boot reconcile did not report the cleared session",
    );
    assert_eq!(
        *platform
            .auth_states
            .lock()
            .expect("auth state list mutex poisoned"),
        vec![AuthState::Disconnected]
    );
}

#[test]
fn session_store_sync_clears_unreadable_blob() {
    let session_clears = Arc::new(Mutex::new(0));
    let (host, pairing_host) = ProductRuntimeHost::new_compat_with_pairing(
        Arc::new(StubPlatform {
            session_error: Some("storage unavailable"),
            session_clears: session_clears.clone(),
            ..Default::default()
        }),
        test_spawner(),
    );
    install_pairing_session(&host, sso_session_info());

    pairing_host
        .clone()
        .start_session_store_sync_for_tests(test_spawner());
    wait_until(
        || *session_clears.lock().unwrap() == 1,
        "session store sync did not clear unreadable blob",
    );

    assert!(host.test_session_state().current().is_none());
    assert_eq!(*session_clears.lock().unwrap(), 1);
}

/// A persistently failing read clears the backing store once at boot.
/// Further clears require explicit host notifications.
#[test]
fn session_store_sync_clears_once_on_initial_persistent_read_error() {
    let session_clears = Arc::new(Mutex::new(0));
    let (host, pairing_host) = ProductRuntimeHost::new_compat_with_pairing(
        Arc::new(StubPlatform {
            session_error: Some("storage unavailable"),
            session_clears: session_clears.clone(),
            ..Default::default()
        }),
        test_spawner(),
    );
    install_pairing_session(&host, sso_session_info());

    pairing_host
        .clone()
        .start_session_store_sync_for_tests(test_spawner());

    wait_until(
        || *session_clears.lock().unwrap() == 1,
        "clear_stored_session was never called",
    );
    assert_eq!(*session_clears.lock().unwrap(), 1);
    assert!(host.test_session_state().current().is_none());
}

#[test]
fn disconnect_submits_disconnected_message_best_effort() {
    let platform = Arc::new(StubPlatform::default());
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    let session = sso_session_info();
    install_pairing_session(&host, session.clone());

    futures::executor::block_on(host.disconnect());

    assert!(host.test_session_state().current().is_none());
    assert_eq!(
        *platform
            .session_clears
            .lock()
            .expect("session clear counter mutex poisoned"),
        1
    );
    let message = submitted_remote_message(&platform, &session);
    assert_eq!(message.message_id.len(), 8, "opaque nanoid message id");
    assert!(matches!(
        message.data,
        RemoteMessageData::V1(v1::RemoteMessage::Disconnected)
    ));
}

#[test]
fn pairing_logout_clears_session_and_bootstrap_identity() {
    let platform = Arc::new(StubPlatform::default());
    let (host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());
    install_pairing_session(&host, sso_session_info());
    {
        let mut storage = platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned");
        storage.insert(
            core_storage_test_key(CoreStorageKey::PairingDeviceIdentity),
            vec![1, 2, 3],
        );
        storage.insert(
            core_storage_test_key(CoreStorageKey::LastProcessedPairingStatement),
            vec![4, 5, 6],
        );
    }

    futures::executor::block_on(pairing_host.logout_and_reset_pairing()).unwrap();

    assert!(host.test_session_state().current().is_none());
    let storage = platform
        .local_storage
        .lock()
        .expect("local storage mutex poisoned");
    assert!(!storage.contains_key(&core_storage_test_key(
        CoreStorageKey::PairingDeviceIdentity
    )));
    assert!(!storage.contains_key(&core_storage_test_key(
        CoreStorageKey::LastProcessedPairingStatement
    )));
}

#[test]
fn disconnect_clears_session_store_and_broadcasts_disconnected() {
    let platform = Arc::new(StubPlatform::default());
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());
    install_pairing_session(&host, sso_session_info());
    platform
        .local_storage
        .lock()
        .expect("local storage mutex poisoned")
        .insert(
            core_storage_test_key(CoreStorageKey::PairingDeviceIdentity),
            vec![1, 2, 3],
        );
    let mut statuses = host.test_session_state().subscribe();
    assert_eq!(
        futures::executor::block_on(statuses.next()).unwrap(),
        HostAccountConnectionStatusSubscribeItem::V1(
            v01::HostAccountConnectionStatusSubscribeItem::Connected
        )
    );

    futures::executor::block_on(host.disconnect());

    assert!(host.test_session_state().current().is_none());
    assert_eq!(
        *platform
            .session_clears
            .lock()
            .expect("session clear counter mutex poisoned"),
        1
    );
    assert!(
        platform
            .local_storage
            .lock()
            .expect("local storage mutex poisoned")
            .contains_key(&core_storage_test_key(
                CoreStorageKey::PairingDeviceIdentity
            )),
        "logout may leave the old pairing identity in storage; the next login rotates it before presenting QR"
    );
    assert_eq!(
        futures::executor::block_on(statuses.next()).unwrap(),
        HostAccountConnectionStatusSubscribeItem::V1(
            v01::HostAccountConnectionStatusSubscribeItem::Disconnected
        )
    );
    // `set_session` bypasses the auth state cell, so the cell never left
    // `Disconnected` and the logout emits nothing new. Only a session
    // activation announces an unchanged state.
    assert!(
        platform
            .auth_states
            .lock()
            .expect("auth state list mutex poisoned")
            .is_empty()
    );
}

#[test]
fn disconnect_emits_disconnected_auth_state_after_store_sync_connected() {
    let stored = sso_session_info();
    let platform = Arc::new(StubPlatform {
        session_blob: Some(crate::host_logic::session::encode_persisted_session(
            &stored,
        )),
        ..Default::default()
    });
    let (host, pairing_host) =
        ProductRuntimeHost::new_compat_with_pairing(platform.clone(), test_spawner());
    pairing_host
        .clone()
        .start_session_store_sync_for_tests(test_spawner());
    wait_until(
        || {
            platform
                .auth_states
                .lock()
                .expect("auth state list mutex poisoned")
                .len()
                == 1
        },
        "session store sync did not emit connected auth state",
    );

    futures::executor::block_on(host.disconnect());

    assert_eq!(
        *platform
            .auth_states
            .lock()
            .expect("auth state list mutex poisoned"),
        vec![
            AuthState::Connected(connected_session_ui_info(&stored)),
            AuthState::Disconnected,
        ]
    );
}

#[test]
fn disconnect_tolerates_repeated_logout_when_already_disconnected() {
    let platform = Arc::new(StubPlatform::default());
    let host = ProductRuntimeHost::new_compat(platform.clone(), test_spawner());

    futures::executor::block_on(host.disconnect());
    futures::executor::block_on(host.disconnect());

    assert!(host.test_session_state().current().is_none());
    assert_eq!(
        *platform
            .session_clears
            .lock()
            .expect("session clear counter mutex poisoned"),
        2
    );
    assert!(platform.sent_rpc.lock().unwrap().is_empty());
}

#[test]
fn permissions_grants_and_caches() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let request = HostDevicePermissionRequest::V1(v01::HostDevicePermissionRequest::Camera);
    let response =
        futures::executor::block_on(host.request_device_permission(&cx, request)).unwrap();
    let HostDevicePermissionResponse::V1(inner) = response;
    assert!(inner.granted);
}

#[test]
fn feature_supported_encodes_response_to_known_bytes() {
    let host = ProductRuntimeHost::new_compat(stub_platform(), test_spawner());
    let cx = CallContext::default();
    let request = HostFeatureSupportedRequest::V1(v01::HostFeatureSupportedRequest::Chain {
        genesis_hash: vec![0u8; 32],
    });
    let response = futures::executor::block_on(host.feature_supported(&cx, request)).unwrap();
    // [V1 variant=0][supported=1]
    assert_eq!(response.encode(), vec![0x00, 0x01]);
}

mod signing;
