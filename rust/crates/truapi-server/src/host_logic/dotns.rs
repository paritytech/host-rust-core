//! dotns URL parsing, normalization, and classification.
//!
//! The Rust core owns the whole decision so every platform host sees the
//! same categorization and the `navigate_to` callback only receives
//! already-validated input.

use truapi_platform::{has_dotns_tld, normalize_remote_domain};
use unicode_normalization::UnicodeNormalization;
use url::{Url, form_urlencoded};

/// What a `/-/pocket/...` deeplink asks the host to do.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(not(target_arch = "wasm32"), derive(uniffi::Enum))]
pub enum PocketDeeplinkAction {
    /// Offer to add a published card, behind the host's approval dialog.
    Add,
    /// Expand a card that is already present.
    Open,
}

/// How the input URL should be opened. Kept in one enum rather than passing
/// a raw string so the dispatcher can reject invalid input before reaching
/// any platform callback. The open variants carry the ready-to-load canonical
/// URL; `DotName` and `Localhost` keep the dotns/localhost identity visible so
/// env-aware hosts can rewrite dotNS names for their active environment and
/// re-parse without losing information.
#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(not(target_arch = "wasm32"), derive(uniffi::Enum))]
pub enum NavigateDecision {
    /// A dotNS identifier plus path/query/hash suffix (no leading `/`).
    DotName {
        /// Lower-cased dotNS host (e.g. `mytestapp.dot`).
        identifier: String,
        /// Path/query/hash suffix without a leading `/`.
        path: String,
        /// Loadable `https://` URL for this decision.
        canonical_url: String,
    },
    /// A `localhost[:port]` URL plus path/query/hash suffix (no leading `/`).
    Localhost {
        /// `localhost` with optional `:port` suffix.
        host: String,
        /// Path/query/hash suffix without a leading `/`.
        path: String,
        /// Loadable `http://` URL for this decision.
        canonical_url: String,
    },
    /// A dotNS product's host-handled Pocket target. The first path segment
    /// `-` is reserved for these, so no App route can shadow one.
    Pocket {
        /// Lower-cased dotNS host of the product that backs the card.
        identifier: String,
        /// Requested Pocket action.
        action: PocketDeeplinkAction,
        /// Card named by the `card` query parameter.
        card_id: String,
        /// Normalized `polkadot://` form of the deeplink, which is what
        /// `navigate_to` hands the host. The card id is percent-encoded, so
        /// re-parsing this names the same card.
        canonical_url: String,
    },
    /// An absolute external URL with an `http(s):` scheme prepended if missing.
    External {
        /// Canonical URL string.
        url: String,
    },
    /// Input that fails every branch: empty, unparseable, or a dotNS URL
    /// carrying port/userinfo (both forbidden since dotns resolves via the
    /// chain and has no notion of either).
    Reject {
        /// Human-readable reason for the rejection.
        reason: String,
    },
}

fn join_url(scheme: &str, host: &str, path: &str) -> String {
    if path.is_empty() {
        format!("{scheme}{host}")
    } else {
        format!("{scheme}{host}/{path}")
    }
}

/// Classify a URL the way the host navigation handler does: try dotNS first,
/// then `localhost`, then normalize as external.
pub fn parse_navigate(input: &str) -> NavigateDecision {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return NavigateDecision::Reject {
            reason: "empty input".to_string(),
        };
    }

    if let Some(decision) = classify_dotns(trimmed) {
        return decision;
    }

    if let Some(decision) = classify_localhost(trimmed) {
        return decision;
    }

    match normalize_external(trimmed) {
        Ok(url) => NavigateDecision::External { url },
        Err(reason) => NavigateDecision::Reject { reason },
    }
}

/// Canonical host form: case-folded and NFC-normalized (belt-and-suspenders;
/// `url` already applies IDNA to parsed hosts), with a trailing root dot
/// dropped so the absolute form `example.dot.` keys identically to
/// `example.dot`.
fn normalize_host(host: &str) -> String {
    let normalized: String = host.nfc().collect::<String>().to_lowercase();
    normalized
        .strip_suffix('.')
        .unwrap_or(&normalized)
        .to_string()
}

/// dotNS TLD check, applied to the [`normalize_host`] form so `Example.DOT`
/// and the trailing-dot FQDN `example.dot.` classify like `example.dot`.
/// Shares [`truapi_platform::DOTNS_TLDS`] with product-identifier validation
/// so navigation and derivation accept the same per-network names.
fn is_dotns_domain(host: &str) -> bool {
    has_dotns_tld(&normalize_host(host))
}

fn parse_with_explicit_https(input: &str) -> Option<Url> {
    if let Ok(direct) = Url::parse(input) {
        return Some(direct);
    }
    Url::parse(&format!("https://{input}")).ok()
}

/// Recognize dotNS URLs (including the `polkadot://` scheme). Returns:
/// - `Some(DotName)` for a clean dotNS URL
/// - `Some(Reject)` for a dotNS URL with port or userinfo
/// - `None` when the input isn't a dotNS URL (caller falls through to
///   localhost / external)
fn classify_dotns(input: &str) -> Option<NavigateDecision> {
    let parsed = if input.starts_with("polkadot://") {
        Url::parse(input).ok()?
    } else {
        parse_with_explicit_https(input)?
    };

    let hostname = parsed.host_str()?;
    if !is_dotns_domain(hostname) {
        return None;
    }

    if parsed.port().is_some() || !parsed.username().is_empty() || parsed.password().is_some() {
        return Some(NavigateDecision::Reject {
            reason: format!("{hostname} carries port or userinfo; dotns forbids both"),
        });
    }

    let identifier = normalize_host(hostname);
    if let Some(decision) = classify_host_target(&parsed, &identifier) {
        return Some(decision);
    }

    let path = strip_leading_slash(parsed.path()) + &suffix(&parsed);
    let canonical_url = join_url("https://", &identifier, &path);
    Some(NavigateDecision::DotName {
        identifier,
        path,
        canonical_url,
    })
}

/// Recognize the reserved `/-/` namespace, which names a host modality rather
/// than an App route. `None` sends the path to the App, either because it is
/// an ordinary route or because it names a target this core does not serve.
fn classify_host_target(url: &Url, identifier: &str) -> Option<NavigateDecision> {
    let mut segments = url.path_segments()?;
    if segments.next() != Some("-") {
        return None;
    }
    let target: Vec<&str> = segments.filter(|segment| !segment.is_empty()).collect();
    // A modality or an action this core does not serve opens the App, so a
    // deeplink minted for a newer host degrades rather than failing.
    let (action, verb) = match target.as_slice() {
        ["pocket", "add"] => (PocketDeeplinkAction::Add, "add"),
        ["pocket", "open"] => (PocketDeeplinkAction::Open, "open"),
        _ => return None,
    };
    let card_id = url
        .query_pairs()
        .find(|(key, _)| key == "card")
        .map(|(_, value)| value.into_owned())
        .filter(|card_id| !card_id.is_empty());
    // A known action whose only argument is missing is a malformed link, not a
    // target this core lacks, so it is refused rather than sent to the App.
    let Some(card_id) = card_id else {
        return Some(NavigateDecision::Reject {
            reason: "pocket deeplink names no card".to_string(),
        });
    };
    // `card` arrives percent-decoded, so it is encoded again here: a raw `#`
    // or `&` in a card id would make the canonical form parse as a different
    // deeplink.
    let card = form_urlencoded::byte_serialize(card_id.as_bytes()).collect::<String>();
    Some(NavigateDecision::Pocket {
        identifier: identifier.to_string(),
        action,
        canonical_url: format!("polkadot://{identifier}/-/pocket/{verb}?card={card}"),
        card_id,
    })
}

/// Recognize `localhost[:port]` URLs, with or without an explicit scheme.
fn classify_localhost(input: &str) -> Option<NavigateDecision> {
    let with_scheme = if input.starts_with("localhost") {
        format!("http://{input}")
    } else {
        input.to_string()
    };

    let parsed = Url::parse(&with_scheme).ok()?;
    if parsed.host_str()? != "localhost" {
        return None;
    }

    let host = match parsed.port() {
        Some(port) => format!("localhost:{port}"),
        None => "localhost".to_string(),
    };

    let path = strip_leading_slash(parsed.path()) + &suffix(&parsed);
    let canonical_url = join_url("http://", &host, &path);
    Some(NavigateDecision::Localhost {
        host,
        path,
        canonical_url,
    })
}

/// External URL scheme allowlist. Anything outside this set is treated as
/// a [`NavigateDecision::Reject`] so dangerous schemes (`javascript:`,
/// `data:`, `file:`, `vbscript:`, ...) cannot reach `Platform::navigate_to`.
const ALLOWED_EXTERNAL_SCHEMES: &[&str] = &["http", "https", "mailto", "tel", "polkadot", "dot"];

/// Mirrors `normalizeUrl`: prepend `https://` if missing, otherwise pass the
/// URL through as its canonical string form. Returns `Err(reason)` for an
/// unparseable input or a scheme outside [`ALLOWED_EXTERNAL_SCHEMES`].
fn normalize_external(input: &str) -> Result<String, String> {
    // `parse_with_explicit_https` returns a successful direct parse as-is and
    // only prepends `https://` when the direct parse fails, so a disallowed
    // scheme (e.g. `javascript:`) is never rewritten to https: the single
    // scheme check below rejects it.
    let url = parse_with_explicit_https(input)
        .ok_or_else(|| "URL constructor rejected input".to_string())?;
    if !ALLOWED_EXTERNAL_SCHEMES.contains(&url.scheme()) {
        return Err(format!("scheme `{}` is not allowed", url.scheme()));
    }
    Ok(url.to_string())
}

/// Authorizable domain of an already-canonical [`NavigateDecision::External`]
/// URL, in the [`normalize_remote_domain`] form the permission store keys on.
///
/// Only `http` and `https` address an internet origin that a domain grant can
/// speak about. The rest of [`ALLOWED_EXTERNAL_SCHEMES`] are handoffs to
/// another app — `mailto:` and `tel:` have no host at all, `polkadot:` and
/// `dot:` name an in-ecosystem target — so they return `None`, and the
/// permission gate lets them through instead of inventing a domain for them.
pub fn external_host(url: &str) -> Option<String> {
    let parsed = Url::parse(url).ok()?;
    if !matches!(parsed.scheme(), "http" | "https") {
        return None;
    }
    let host = parsed.host_str()?;
    if host.is_empty() {
        return None;
    }
    Some(normalize_remote_domain(host))
}

fn strip_leading_slash(path: &str) -> String {
    path.strip_prefix('/').unwrap_or(path).to_string()
}

fn suffix(url: &Url) -> String {
    let mut out = String::new();
    if let Some(q) = url.query() {
        out.push('?');
        out.push_str(q);
    }
    if let Some(f) = url.fragment() {
        out.push('#');
        out.push_str(f);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    enum Expected {
        Decision(NavigateDecision),
        AnyExternalOrReject,
        Reject,
    }

    struct TestCase {
        name: &'static str,
        input: &'static str,
        expected: Expected,
    }

    fn dot(identifier: &str, path: &str) -> Expected {
        Expected::Decision(NavigateDecision::DotName {
            identifier: identifier.to_string(),
            path: path.to_string(),
            canonical_url: join_url("https://", identifier, path),
        })
    }

    /// Only for card ids that need no percent-encoding;
    /// `pocket_canonical_url_reencodes_the_card_id` covers the ones that do.
    fn pocket(identifier: &str, action: PocketDeeplinkAction, card_id: &str) -> Expected {
        let verb = match action {
            PocketDeeplinkAction::Add => "add",
            PocketDeeplinkAction::Open => "open",
        };
        Expected::Decision(NavigateDecision::Pocket {
            identifier: identifier.to_string(),
            action,
            card_id: card_id.to_string(),
            canonical_url: format!("polkadot://{identifier}/-/pocket/{verb}?card={card_id}"),
        })
    }

    fn localhost(host: &str, path: &str) -> Expected {
        Expected::Decision(NavigateDecision::Localhost {
            host: host.to_string(),
            path: path.to_string(),
            canonical_url: join_url("http://", host, path),
        })
    }

    fn external(url: &str) -> Expected {
        Expected::Decision(NavigateDecision::External {
            url: url.to_string(),
        })
    }

    #[test]
    fn parse_navigate_cases() {
        let cases = vec![
            TestCase {
                name: "dot bare",
                input: "mytestapp.dot",
                expected: dot("mytestapp.dot", ""),
            },
            TestCase {
                name: "dot trailing root dot",
                input: "example.dot.",
                expected: dot("example.dot", ""),
            },
            TestCase {
                name: "dot trailing root dot with path",
                input: "https://example.dot./path",
                expected: dot("example.dot", "path"),
            },
            TestCase {
                name: "dot li is external",
                input: "mytestapp.dot.li",
                expected: external("https://mytestapp.dot.li/"),
            },
            TestCase {
                name: "dot with https",
                input: "https://mytestapp.dot",
                expected: dot("mytestapp.dot", ""),
            },
            TestCase {
                name: "dot with http",
                input: "http://mytestapp.dot",
                expected: dot("mytestapp.dot", ""),
            },
            TestCase {
                name: "dot with path",
                input: "mytestapp.dot/some/path",
                expected: dot("mytestapp.dot", "some/path"),
            },
            TestCase {
                name: "dot with query only",
                input: "pr508.faucet.dot?embed=1",
                expected: dot("pr508.faucet.dot", "?embed=1"),
            },
            TestCase {
                name: "dot with hash only",
                input: "pr508.faucet.dot#section=main",
                expected: dot("pr508.faucet.dot", "#section=main"),
            },
            TestCase {
                name: "dot with path query hash",
                input: "pr508.faucet.dot/nested/path?embed=1#frame=compact",
                expected: dot("pr508.faucet.dot", "nested/path?embed=1#frame=compact"),
            },
            TestCase {
                name: "polkadot scheme dot host",
                input: "polkadot://currenthost.dot/mytestapp.dot",
                expected: dot("currenthost.dot", "mytestapp.dot"),
            },
            TestCase {
                name: "pocket add deeplink",
                input: "polkadot://game.dot/-/pocket/add?card=loyalty",
                expected: pocket("game.dot", PocketDeeplinkAction::Add, "loyalty"),
            },
            TestCase {
                name: "pocket open deeplink over the https spelling",
                input: "https://Game.DOT/-/pocket/open?card=loyalty",
                expected: pocket("game.dot", PocketDeeplinkAction::Open, "loyalty"),
            },
            TestCase {
                name: "pocket deeplink without a card is rejected",
                input: "polkadot://game.dot/-/pocket/add",
                expected: Expected::Reject,
            },
            TestCase {
                name: "a modality this core does not serve opens the app",
                input: "polkadot://game.dot/-/wallet/open",
                expected: dot("game.dot", "-/wallet/open"),
            },
            TestCase {
                name: "a pocket action this core does not know opens the app",
                input: "polkadot://game.dot/-/pocket/frobnicate?card=loyalty",
                expected: dot("game.dot", "-/pocket/frobnicate?card=loyalty"),
            },
            TestCase {
                name: "bare reserved segment opens the app",
                input: "polkadot://game.dot/-",
                expected: dot("game.dot", "-"),
            },
            TestCase {
                name: "a dash inside an ordinary path is an app route",
                input: "polkadot://game.dot/shop/-/pocket",
                expected: dot("game.dot", "shop/-/pocket"),
            },
            TestCase {
                name: "polkadot scheme non dot host falls through",
                input: "polkadot://example.com/settings",
                expected: Expected::AnyExternalOrReject,
            },
            TestCase {
                name: "polkadot scheme with path",
                input: "polkadot://currenthost.dot/mytestapp.dot/settings",
                expected: dot("currenthost.dot", "mytestapp.dot/settings"),
            },
            TestCase {
                name: "polkadot scheme with query and hash",
                input: "polkadot://currenthost.dot/mytestapp.dot?embed=1#frame=compact",
                expected: dot("currenthost.dot", "mytestapp.dot?embed=1#frame=compact"),
            },
            TestCase {
                name: "dot subdomain",
                input: "sub.acme.dot/path",
                expected: dot("sub.acme.dot", "path"),
            },
            TestCase {
                name: "dot mixed case",
                input: "Example.DOT/Path",
                expected: dot("example.dot", "Path"),
            },
            TestCase {
                name: "dot with port is rejected",
                input: "https://x.dot:8080/path",
                expected: Expected::Reject,
            },
            TestCase {
                name: "dot with userinfo is rejected",
                input: "https://user:pass@x.dot/path",
                expected: Expected::Reject,
            },
            TestCase {
                name: "paseo bare",
                input: "mytestapp.paseo",
                expected: dot("mytestapp.paseo", ""),
            },
            TestCase {
                name: "paseo with path query hash",
                input: "pr508.faucet.paseo/nested/path?embed=1#frame=compact",
                expected: dot("pr508.faucet.paseo", "nested/path?embed=1#frame=compact"),
            },
            TestCase {
                name: "paseo mixed case",
                input: "Example.PASEO/Path",
                expected: dot("example.paseo", "Path"),
            },
            TestCase {
                name: "polkadot scheme paseo host",
                input: "polkadot://currenthost.paseo/mytestapp.paseo",
                expected: dot("currenthost.paseo", "mytestapp.paseo"),
            },
            TestCase {
                name: "paseo with port is rejected",
                input: "https://x.paseo:8443/path",
                expected: Expected::Reject,
            },
            TestCase {
                name: "paseo with userinfo is rejected",
                input: "https://user:pass@x.paseo/path",
                expected: Expected::Reject,
            },
            TestCase {
                name: "testnet bare",
                input: "browse.testnet",
                expected: dot("browse.testnet", ""),
            },
            TestCase {
                name: "testnet mixed case with path",
                input: "Browse.TESTNET/Path",
                expected: dot("browse.testnet", "Path"),
            },
            TestCase {
                name: "polkadot scheme testnet host",
                input: "polkadot://currenthost.testnet/browse.testnet",
                expected: dot("currenthost.testnet", "browse.testnet"),
            },
            TestCase {
                name: "testnet with port is rejected",
                input: "https://x.testnet:8443/path",
                expected: Expected::Reject,
            },
            TestCase {
                name: "testnet with userinfo is rejected",
                input: "https://user:pass@x.testnet/path",
                expected: Expected::Reject,
            },
            TestCase {
                name: "trim whitespace",
                input: "  mytestapp.dot/path  ",
                expected: dot("mytestapp.dot", "path"),
            },
            TestCase {
                name: "localhost bare with port",
                input: "localhost:3000",
                expected: localhost("localhost:3000", ""),
            },
            TestCase {
                name: "localhost with port and path",
                input: "localhost:3000/some/path",
                expected: localhost("localhost:3000", "some/path"),
            },
            TestCase {
                name: "localhost with explicit http",
                input: "http://localhost:5000",
                expected: localhost("localhost:5000", ""),
            },
            TestCase {
                name: "localhost with http and path",
                input: "http://localhost:5000/path",
                expected: localhost("localhost:5000", "path"),
            },
            TestCase {
                name: "localhost with query and hash",
                input: "localhost:3000/path?q=1#h",
                expected: localhost("localhost:3000", "path?q=1#h"),
            },
            TestCase {
                name: "localhost without port",
                input: "localhost",
                expected: localhost("localhost", ""),
            },
            TestCase {
                name: "localhost without port with path",
                input: "localhost/path",
                expected: localhost("localhost", "path"),
            },
            TestCase {
                name: "external bare domain",
                input: "google.com",
                expected: external("https://google.com/"),
            },
            TestCase {
                name: "external bare domain with path",
                input: "google.com/search?q=test",
                expected: external("https://google.com/search?q=test"),
            },
            TestCase {
                name: "external preserves https",
                input: "https://example.com/page",
                expected: external("https://example.com/page"),
            },
            TestCase {
                name: "external preserves http",
                input: "http://example.com/page",
                expected: external("http://example.com/page"),
            },
            TestCase {
                name: "external dot li",
                input: "acme.dot.li/path/1",
                expected: external("https://acme.dot.li/path/1"),
            },
            TestCase {
                name: "reject empty",
                input: "",
                expected: Expected::Reject,
            },
            TestCase {
                name: "reject whitespace",
                input: "   ",
                expected: Expected::Reject,
            },
            TestCase {
                name: "reject unparseable",
                input: ":::invalid",
                expected: Expected::Reject,
            },
            TestCase {
                name: "reject javascript URI",
                input: "javascript:alert(1)",
                expected: Expected::Reject,
            },
            TestCase {
                name: "reject file URI",
                input: "file:///etc/passwd",
                expected: Expected::Reject,
            },
            TestCase {
                name: "reject data URI",
                input: "data:text/html,<script>alert(1)</script>",
                expected: Expected::Reject,
            },
            TestCase {
                name: "reject vbscript URI",
                input: "vbscript:msgbox(1)",
                expected: Expected::Reject,
            },
        ];

        for case in cases {
            let actual = parse_navigate(case.input);
            match case.expected {
                Expected::Decision(expected) => assert_eq!(actual, expected, "{}", case.name),
                Expected::AnyExternalOrReject => assert!(
                    matches!(
                        actual,
                        NavigateDecision::External { .. } | NavigateDecision::Reject { .. }
                    ),
                    "{}: expected External or Reject, got {actual:?}",
                    case.name,
                ),
                Expected::Reject => assert!(
                    matches!(actual, NavigateDecision::Reject { .. }),
                    "{}: expected Reject, got {actual:?}",
                    case.name,
                ),
            }
        }

        let nfc = parse_navigate("café.dot");
        let nfd = parse_navigate("cafe\u{0301}.dot");
        match (&nfc, &nfd) {
            (
                NavigateDecision::DotName { identifier: a, .. },
                NavigateDecision::DotName { identifier: b, .. },
            ) => assert_eq!(a, b, "NFC and NFD inputs must normalize to one identifier"),
            other => panic!("expected two DotName decisions, got {other:?}"),
        }
    }

    #[test]
    fn pocket_canonical_url_reencodes_the_card_id() {
        // `card` arrives percent-decoded, so a card id carrying URL syntax
        // would otherwise re-parse as a different deeplink: `#` starts a
        // fragment and `&` starts a second parameter.
        for (input, expected) in [
            (
                "polkadot://game.dot/-/pocket/add?card=a%23b",
                "polkadot://game.dot/-/pocket/add?card=a%23b",
            ),
            (
                "polkadot://game.dot/-/pocket/open?card=a%26open%3Dx",
                "polkadot://game.dot/-/pocket/open?card=a%26open%3Dx",
            ),
        ] {
            match parse_navigate(input) {
                NavigateDecision::Pocket {
                    canonical_url,
                    card_id,
                    ..
                } => {
                    assert_eq!(canonical_url, expected, "canonical url for {input}");
                    // Re-parsing the canonical form has to name the same card.
                    match parse_navigate(&canonical_url) {
                        NavigateDecision::Pocket { card_id: again, .. } => {
                            assert_eq!(again, card_id, "round trip for {input}")
                        }
                        other => panic!("canonical url stopped being a Pocket target: {other:?}"),
                    }
                }
                other => panic!("expected a Pocket decision for {input}, got {other:?}"),
            }
        }
    }

    #[test]
    fn external_host_names_a_domain_only_for_http_schemes() {
        assert_eq!(
            external_host("https://api.example.com/page"),
            Some("api.example.com".to_string())
        );
        assert_eq!(
            external_host("http://Example.COM./"),
            Some("example.com".to_string())
        );
        // The permission store keys punycode, so a non-ASCII host resolves to
        // the same slot as its ASCII spelling.
        assert_eq!(
            external_host("https://bücher.example/"),
            external_host("https://xn--bcher-kva.example/")
        );
        // Handoff schemes address another app, not a domain a grant can name.
        for handoff in [
            "mailto:someone@example.com",
            "tel:+15551234567",
            "polkadot://1exampleaddress",
            "dot:transfer",
        ] {
            assert_eq!(
                external_host(handoff),
                None,
                "{handoff} is not a web origin"
            );
        }
    }
}
