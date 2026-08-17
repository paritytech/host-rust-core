//! Compile-time check that the `Platform` super-trait composes its capability
//! traits with `Send + Sync + 'static` bounds and remains object-safe via
//! `async_trait`.

use truapi_platform::{
    HostInfo, HostRuntimeConfig, PairingHostConfig, Platform, PlatformInfo, ProductContext,
    ProductStorageKey, RuntimeConfigValidationError,
};

fn _assert_platform_bounds<T: Platform + Send + Sync + 'static>() {}

fn _assert_platform_object_safe(_: &(dyn Platform + 'static)) {}

#[test]
fn runtime_config_validation_cases() {
    struct TestCase {
        name: &'static str,
        host_name: &'static str,
        host_icon: Option<&'static str>,
        expected: Result<(), RuntimeConfigValidationError>,
    }

    let cases = vec![
        TestCase {
            name: "accepts HTTPS host icon",
            host_name: "Polkadot Web",
            host_icon: Some("https://dot.li/dotli.png"),
            expected: Ok(()),
        },
        TestCase {
            name: "rejects empty host name",
            host_name: " ",
            host_icon: Some("https://dot.li/dotli.png"),
            expected: Err(RuntimeConfigValidationError::EmptyField {
                field: "host_info.name",
            }),
        },
        TestCase {
            name: "rejects relative host icon",
            host_name: "Polkadot Web",
            host_icon: Some("/dotli.png"),
            expected: Err(RuntimeConfigValidationError::InvalidHostIcon {
                source: url::ParseError::RelativeUrlWithoutBase,
            }),
        },
        TestCase {
            name: "rejects non-HTTPS host icon",
            host_name: "Polkadot Web",
            host_icon: Some("http://localhost:3000/dotli.png"),
            expected: Err(RuntimeConfigValidationError::InsecureHostIcon {
                scheme: "http".to_string(),
            }),
        },
    ];

    for case in cases {
        let result = HostRuntimeConfig::new(
            HostInfo {
                name: case.host_name.to_string(),
                icon: case.host_icon.map(str::to_string),
                version: None,
            },
            PlatformInfo::default(),
        )
        .map(|_| ());
        assert_eq!(result, case.expected, "{}", case.name);
    }
}

#[test]
fn pairing_config_validation_cases() {
    struct TestCase {
        name: &'static str,
        host_name: &'static str,
        host_icon: Option<&'static str>,
        pairing_deeplink_scheme: &'static str,
        expected: Result<(), RuntimeConfigValidationError>,
    }

    let cases = vec![TestCase {
        name: "rejects malformed deeplink scheme",
        host_name: "Polkadot Web",
        host_icon: Some("https://dot.li/dotli.png"),
        pairing_deeplink_scheme: "polkadotapp://",
        expected: Err(RuntimeConfigValidationError::InvalidDeeplinkScheme {
            scheme: "polkadotapp://".to_string(),
        }),
    }];

    for case in cases {
        let result = PairingHostConfig::new(
            HostInfo {
                name: case.host_name.to_string(),
                icon: case.host_icon.map(str::to_string),
                version: None,
            },
            PlatformInfo::default(),
            [0xa2; 32],
            [0xbb; 32],
            case.pairing_deeplink_scheme.to_string(),
        )
        .map(|_| ());
        assert_eq!(result, case.expected, "{}", case.name);
    }
}

#[test]
fn product_context_validation_cases() {
    let dotli = ProductContext::new("Dotli.DOT".to_string()).expect("dot product id is valid");
    assert_eq!(dotli.product_id, "dotli.dot");

    let localhost =
        ProductContext::new(" localhost:3000 ".to_string()).expect("localhost product id is valid");
    assert_eq!(localhost.product_id, "localhost:3000");

    assert_eq!(
        ProductContext::new("localhost".to_string()).map(|context| context.product_id),
        Ok("localhost".to_string())
    );
    assert_eq!(
        ProductContext::new("dotli.dot".to_string()).map(|_| ()),
        Ok(())
    );
    assert_eq!(
        ProductContext::new("Host-Playground44.PASEO".to_string())
            .map(|context| context.product_id),
        Ok("host-playground44.paseo".to_string())
    );
    for domain in ["example.com", "example.org", "dotli.dotty"] {
        assert_eq!(
            ProductContext::new(domain.to_string()).map(|_| ()),
            Err(RuntimeConfigValidationError::InvalidProductId {
                product_id: domain.to_string(),
            }),
            "{domain} must not be accepted as a product identifier"
        );
    }
    assert_eq!(
        ProductContext::new(" ".to_string()).map(|_| ()),
        Err(RuntimeConfigValidationError::EmptyField {
            field: "product_id",
        })
    );
}

#[test]
fn product_storage_key_round_trips_scopes_and_arbitrary_keys() {
    let key = ProductStorageKey::new("Tést.DOT", "settings:theme").expect("valid product key");
    let encoded = key.encode();
    let decoded = ProductStorageKey::decode(&encoded).expect("decode product key");

    assert_eq!(decoded.product_id(), "tést.dot");
    assert_eq!(decoded.key(), "settings:theme");
    assert_eq!(decoded, key);
    assert!(ProductStorageKey::decode("unknown:key").is_err());
}

#[test]
fn chat_icons_accept_only_https_and_inline_images() {
    for hostile in [
        "javascript:alert(1)",
        "\u{0}javascript:alert(1)",
        "java\u{9}script:alert(1)",
        "JavaScript:alert(1)",
        "vbscript:msgbox(1)",
        "file:///etc/passwd",
        "fi\u{9}le:///etc/passwd",
        "data:text/html,<script>alert(1)</script>",
        "data: text/html,<script>alert(1)</script>",
        "data:\ttext/html;base64,AAAA",
        "data: TEXT/HTML;base64,AAAA",
        "data:image/svg+xml,<svg onload=alert(1)>",
        "blob:https://evil.example/x",
        "about:blank",
        "intent://evil#Intent;scheme=http;end",
        "content://com.evil/x",
        "//evil.example/x.png",
        "../../../etc/passwd",
        "http://tracker.example/pixel.png",
        "ftp://example.invalid/x.png",
    ] {
        assert!(
            truapi_platform::validate_chat_icon("icon", hostile).is_err(),
            "{hostile:?} must be rejected"
        );
    }

    for allowed in [
        "",
        "   ",
        "https://example.invalid/icon.png",
        "data:image/png;base64,iVBORw0KGgo=",
        "data:image/jpeg;base64,/9j/4AAQ",
        "data:image/gif;base64,R0lGODlh",
        "data:image/webp;base64,UklGRg==",
        "data:image/avif;base64,AAAAGGZ0",
    ] {
        assert!(
            truapi_platform::validate_chat_icon("icon", allowed).is_ok(),
            "{allowed:?} must be accepted"
        );
    }
}

#[test]
fn chat_names_keep_joiners_and_bidi_marks_but_drop_spoofing_controls() {
    for legitimate in [
        "👩‍💻 Devs",
        "👨‍👩‍👧 Family",
        "🏳️‍🌈 Pride",
        "می‌روم",
        "\u{200e}שלום",
        "🎲 Dice",
        "",
    ] {
        assert!(
            truapi_platform::validate_chat_name("name", legitimate).is_ok(),
            "{legitimate:?} must be accepted"
        );
    }

    for spoofing in [
        "a\u{202e}b",
        "a\u{2066}b",
        "a\u{200b}b",
        "a\u{061c}b",
        "a\u{e0041}b",
        "a\u{feff}b",
        "a\u{0}b",
    ] {
        assert!(
            truapi_platform::validate_chat_name("name", spoofing).is_err(),
            "{spoofing:?} must be rejected"
        );
    }
}

#[test]
fn chat_identifiers_normalize_and_bound_the_value_the_host_receives() {
    let nfc = truapi_platform::normalize_chat_identifier("botId", "cafe\u{301}").unwrap();
    assert_eq!(
        nfc,
        truapi_platform::normalize_chat_identifier("botId", "caf\u{e9}").unwrap()
    );

    assert!(truapi_platform::normalize_chat_identifier("botId", "").is_err());
    assert!(truapi_platform::normalize_chat_identifier("botId", "   ").is_err());

    // The cap applies after NFC, which can expand the input.
    let expanding = "\u{1d160}".repeat(64);
    assert!(expanding.len() <= truapi_platform::CHAT_FIELD_MAX_BYTES);
    let rejected = truapi_platform::normalize_chat_identifier("botId", &expanding);
    assert!(
        rejected.is_err(),
        "a value that expands past the cap under NFC must be rejected"
    );

    let oversized = "f".repeat(truapi_platform::CHAT_FIELD_MAX_BYTES + 1);
    assert!(truapi_platform::normalize_chat_identifier("botId", &oversized).is_err());

    let icon = "d".repeat(truapi_platform::CHAT_ICON_MAX_BYTES + 1);
    assert!(truapi_platform::validate_chat_icon("icon", &icon).is_err());
}
