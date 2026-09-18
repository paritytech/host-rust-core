//! Screening for product requests to a host-registered backend.
//!
//! The core never learns which origin a backend identifier resolves to, and
//! does not need to: a product supplies an identifier and a relative path, so
//! it cannot express an origin at all. These rules keep it that way, and reject
//! rather than normalize so no normalizer has to stay in step across the
//! boundary.

use truapi::latest::{
    BackendBody, BackendQueryItem, HostBackendError, HostBackendRequest, HostBackendResponse,
};

/// Longest backend identifier the core forwards.
const MAX_BACKEND_LEN: usize = 64;

/// Longest path the core forwards.
const MAX_PATH_LEN: usize = 2048;

/// Most query parameters the core forwards.
const MAX_QUERY_ITEMS: usize = 64;

/// Largest total query size, summed over every name and value.
const MAX_QUERY_BYTES: usize = 4096;

/// Largest request body the core forwards.
const MAX_BODY_BYTES: usize = 1024 * 1024;

/// Largest response body the core accepts back from a host.
const MAX_RESPONSE_BYTES: usize = 1024 * 1024;

/// Most response headers the core passes to a product.
const MAX_RESPONSE_HEADERS: usize = 8;

/// Longest response header value the core passes to a product.
const MAX_HEADER_VALUE_BYTES: usize = 512;

/// Response headers a product may see: enough to parse the body and to honour a
/// backend asking the caller to slow down. Notably absent are `set-cookie`,
/// which would be ambient authority in the product's realm, and `location`,
/// which would name the origin the tunnel keeps to itself.
const ALLOWED_RESPONSE_HEADERS: &[&str] = &[
    "content-type",
    "retry-after",
    "link",
    "x-ratelimit-limit",
    "x-ratelimit-remaining",
    "x-ratelimit-reset",
];

fn invalid(reason: &str) -> HostBackendError {
    HostBackendError::InvalidRequest {
        reason: reason.to_owned(),
    }
}

/// Screen a product request before it reaches the host.
pub fn screen_request(request: &HostBackendRequest) -> Result<(), HostBackendError> {
    screen_backend(&request.backend)?;
    screen_path(&request.path)?;
    screen_query(&request.query)?;
    screen_body(request.method, request.body.as_ref())
}

/// Screen a host response before it reaches the product. The host owes the
/// allowlist and the size cap; this is what a host that forgets runs into.
pub fn screen_response(response: &mut HostBackendResponse) -> Result<(), HostBackendError> {
    if response.body.len() > MAX_RESPONSE_BYTES {
        return Err(HostBackendError::ResponseTooLarge);
    }
    response.headers.retain(|header| {
        ALLOWED_RESPONSE_HEADERS.contains(&header.name.as_str())
            && header.value.len() <= MAX_HEADER_VALUE_BYTES
            && !header.value.chars().any(|c| c.is_control())
    });
    response.headers.truncate(MAX_RESPONSE_HEADERS);
    Ok(())
}

/// A slug, because a host keys its registry by it and may well log it.
fn screen_backend(backend: &str) -> Result<(), HostBackendError> {
    if backend.is_empty() {
        return Err(invalid("backend must not be empty"));
    }
    if backend.len() > MAX_BACKEND_LEN {
        return Err(invalid("backend is too long"));
    }
    if !backend
        .bytes()
        .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
    {
        return Err(invalid(
            "backend must be lowercase letters, digits and hyphens",
        ));
    }
    if backend.starts_with('-') || backend.ends_with('-') {
        return Err(invalid("backend must not start or end with a hyphen"));
    }
    Ok(())
}

/// The origin guarantee rests here: whatever base URL the host holds, a path
/// that passes this cannot address anything outside it.
fn screen_path(path: &str) -> Result<(), HostBackendError> {
    if !path.starts_with('/') {
        return Err(invalid("path must start with '/'"));
    }
    if path.len() > MAX_PATH_LEN {
        return Err(invalid("path is too long"));
    }
    if !path.is_ascii() {
        return Err(invalid("path must be ASCII; put other bytes in the query"));
    }
    for character in path.chars() {
        match character {
            '?' => return Err(invalid("path must not contain '?'")),
            '#' => return Err(invalid("path must not contain '#'")),
            '\\' => return Err(invalid("path must not contain '\\'")),
            // `%2e%2e%2f` only becomes traversal once a URL parser decodes it.
            '%' => return Err(invalid("path must not contain '%'")),
            ' ' => return Err(invalid("path must not contain spaces")),
            c if c.is_ascii_control() => {
                return Err(invalid("path must not contain control characters"));
            }
            _ => {}
        }
    }
    if path.starts_with("//") {
        return Err(invalid("path must not start with '//'"));
    }
    // The leading `/` opens an empty segment and a single trailing `/` closes
    // one; neither is a real segment, and `/` and `/a/` are both ordinary
    // paths. An empty segment anywhere between them is not.
    for segment in path.strip_suffix('/').unwrap_or(path).split('/').skip(1) {
        if segment.is_empty() {
            return Err(invalid("path must not contain empty segments"));
        }
        if segment == "." || segment == ".." {
            return Err(invalid("path must not contain '.' or '..' segments"));
        }
    }
    Ok(())
}

/// Query parts are screened for size and control characters, not URL syntax,
/// which the host's percent-encoding neutralizes. Names are kept to a plain
/// charset so a host that encodes values but not names cannot be made to inject
/// a parameter.
fn screen_query(query: &[BackendQueryItem]) -> Result<(), HostBackendError> {
    if query.len() > MAX_QUERY_ITEMS {
        return Err(HostBackendError::RequestTooLarge);
    }
    let mut total = 0usize;
    for item in query {
        screen_query_item(item)?;
        total = total.saturating_add(item.name.len() + item.value.len());
    }
    if total > MAX_QUERY_BYTES {
        return Err(HostBackendError::RequestTooLarge);
    }
    Ok(())
}

fn screen_query_item(item: &BackendQueryItem) -> Result<(), HostBackendError> {
    if item.name.is_empty() {
        return Err(invalid("query parameter name must not be empty"));
    }
    if !item
        .name
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'.' | b'-'))
    {
        return Err(invalid(
            "query parameter name must be alphanumeric, '_', '.' or '-'",
        ));
    }
    if item.value.chars().any(|c| c.is_control()) {
        return Err(invalid(
            "query parameters must not contain control characters",
        ));
    }
    Ok(())
}

fn screen_body(
    method: truapi::latest::BackendHttpMethod,
    body: Option<&BackendBody>,
) -> Result<(), HostBackendError> {
    let Some(body) = body else {
        return Ok(());
    };
    if !method.allows_body() {
        return Err(invalid("this method does not carry a body"));
    }
    match body {
        BackendBody::Json { bytes } => {
            if bytes.len() > MAX_BODY_BYTES {
                return Err(HostBackendError::RequestTooLarge);
            }
            // Not parsed: the core owns no JSON grammar, only the promise that
            // what it labels `application/json` is text.
            if core::str::from_utf8(bytes).is_err() {
                return Err(invalid("JSON body must be UTF-8"));
            }
            Ok(())
        }
        BackendBody::Form { fields } => screen_query(fields),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use truapi::latest::{BackendHeader, BackendHttpMethod};

    fn request(backend: &str, path: &str) -> HostBackendRequest {
        HostBackendRequest {
            backend: backend.to_owned(),
            method: BackendHttpMethod::Get,
            path: path.to_owned(),
            query: Vec::new(),
            body: None,
        }
    }

    fn reason(error: HostBackendError) -> String {
        match error {
            HostBackendError::InvalidRequest { reason } => reason,
            other => panic!("expected InvalidRequest, got {other:?}"),
        }
    }

    fn header(name: &str, value: &str) -> BackendHeader {
        BackendHeader {
            name: name.to_owned(),
            value: value.to_owned(),
        }
    }

    #[test]
    fn a_plain_request_passes() {
        let mut plain = request("fiat-onramp", "/service-providers");
        plain.method = BackendHttpMethod::Post;
        plain.query = vec![BackendQueryItem {
            name: "countries".to_owned(),
            value: "DE".to_owned(),
        }];
        plain.body = Some(BackendBody::Json {
            bytes: b"{}".to_vec(),
        });
        assert_eq!(screen_request(&plain), Ok(()));
    }

    #[test]
    fn a_path_cannot_leave_the_backend_origin() {
        for path in [
            "//evil.example.com/steal",
            "/a/../../admin",
            "/..",
            "/./a",
            "service-providers",
            "https://evil.example.com",
            "/a?injected=1",
            "/a#fragment",
            "/a\\b",
            "/a//b",
            "//",
            "/a//",
        ] {
            let error =
                screen_request(&request("fiat-onramp", path)).expect_err("should be refused");
            assert!(
                matches!(error, HostBackendError::InvalidRequest { .. }),
                "path {path} gave {error:?}"
            );
        }
    }

    #[test]
    fn a_percent_escape_is_refused_because_a_url_parser_would_decode_it() {
        for path in [
            "/a/%2e%2e/admin",
            "/a%2fb",
            "/a%5cb",
            "/a%00b",
            "/a%23b",
            "/a%3fb",
            "/already%20encoded",
        ] {
            assert_eq!(
                reason(screen_request(&request("x", path)).unwrap_err()),
                "path must not contain '%'",
                "path {path}"
            );
        }
    }

    #[test]
    fn the_root_and_a_trailing_slash_are_ordinary_paths() {
        for path in ["/", "/a/", "/a/b/"] {
            assert_eq!(screen_request(&request("x", path)), Ok(()), "path {path}");
        }
    }

    #[test]
    fn a_dotted_filename_is_not_a_dot_segment() {
        assert_eq!(screen_request(&request("x", "/a..b/c.json")), Ok(()));
        assert_eq!(screen_request(&request("x", "/...")), Ok(()));
    }

    #[test]
    fn a_path_takes_no_control_characters_spaces_or_non_ascii() {
        assert_eq!(
            reason(screen_request(&request("x", "/a\nb")).unwrap_err()),
            "path must not contain control characters"
        );
        assert_eq!(
            reason(screen_request(&request("x", "/a b")).unwrap_err()),
            "path must not contain spaces"
        );
        assert_eq!(
            reason(screen_request(&request("x", "/café")).unwrap_err()),
            "path must be ASCII; put other bytes in the query"
        );
    }

    #[test]
    fn a_backend_identifier_is_a_slug() {
        assert_eq!(screen_request(&request("fiat-onramp2", "/a")), Ok(()));
        for backend in [
            "",
            "Fiat-Onramp",
            "fiat_onramp",
            "fiat onramp",
            "-onramp",
            "onramp-",
            "fiat/onramp",
            "fiat.onramp",
        ] {
            assert!(
                screen_request(&request(backend, "/a")).is_err(),
                "backend {backend:?} should be refused"
            );
        }
        let long = "a".repeat(MAX_BACKEND_LEN + 1);
        assert_eq!(
            reason(screen_request(&request(&long, "/a")).unwrap_err()),
            "backend is too long"
        );
    }

    #[test]
    fn oversized_parts_are_refused_as_too_large_rather_than_invalid() {
        let mut long_body = request("x", "/a");
        long_body.method = BackendHttpMethod::Post;
        long_body.body = Some(BackendBody::Json {
            bytes: vec![b'a'; MAX_BODY_BYTES + 1],
        });
        assert_eq!(
            screen_request(&long_body),
            Err(HostBackendError::RequestTooLarge)
        );

        let mut many = request("x", "/a");
        many.query = (0..MAX_QUERY_ITEMS + 1)
            .map(|index| BackendQueryItem {
                name: format!("n{index}"),
                value: String::new(),
            })
            .collect();
        assert_eq!(
            screen_request(&many),
            Err(HostBackendError::RequestTooLarge)
        );

        let mut heavy = request("x", "/a");
        heavy.query = vec![BackendQueryItem {
            name: "n".to_owned(),
            value: "v".repeat(MAX_QUERY_BYTES),
        }];
        assert_eq!(
            screen_request(&heavy),
            Err(HostBackendError::RequestTooLarge)
        );

        let long_path = format!("/{}", "a".repeat(MAX_PATH_LEN));
        assert_eq!(
            reason(screen_request(&request("x", &long_path)).unwrap_err()),
            "path is too long"
        );
    }

    #[test]
    fn a_query_name_cannot_inject_a_second_parameter() {
        let mut injected = request("x", "/a");
        injected.query = vec![BackendQueryItem {
            name: "a=1&b".to_owned(),
            value: "v".to_owned(),
        }];
        assert_eq!(
            reason(screen_request(&injected).unwrap_err()),
            "query parameter name must be alphanumeric, '_', '.' or '-'"
        );

        let mut unnamed = request("x", "/a");
        unnamed.query = vec![BackendQueryItem {
            name: String::new(),
            value: "v".to_owned(),
        }];
        assert_eq!(
            reason(screen_request(&unnamed).unwrap_err()),
            "query parameter name must not be empty"
        );

        let mut controlled = request("x", "/a");
        controlled.query = vec![BackendQueryItem {
            name: "n".to_owned(),
            value: "a\r\nX-Injected: 1".to_owned(),
        }];
        assert_eq!(
            reason(screen_request(&controlled).unwrap_err()),
            "query parameters must not contain control characters"
        );
    }

    #[test]
    fn a_query_value_may_carry_url_syntax_because_the_host_encodes_it() {
        let mut item = request("x", "/a");
        item.query = vec![BackendQueryItem {
            name: "q".to_owned(),
            value: "a&b=c#d/../e".to_owned(),
        }];
        assert_eq!(screen_request(&item), Ok(()));
    }

    #[test]
    fn a_repeated_query_name_survives() {
        let mut repeated = request("x", "/a");
        repeated.query = vec![
            BackendQueryItem {
                name: "countries".to_owned(),
                value: "DE".to_owned(),
            },
            BackendQueryItem {
                name: "countries".to_owned(),
                value: "FR".to_owned(),
            },
        ];
        assert_eq!(screen_request(&repeated), Ok(()));
    }

    #[test]
    fn only_the_methods_that_carry_a_body_accept_one() {
        for method in [
            BackendHttpMethod::Get,
            BackendHttpMethod::Head,
            BackendHttpMethod::Delete,
        ] {
            let mut bodied = request("x", "/a");
            bodied.method = method;
            bodied.body = Some(BackendBody::Json {
                bytes: b"{}".to_vec(),
            });
            assert_eq!(
                reason(screen_request(&bodied).unwrap_err()),
                "this method does not carry a body",
                "method {method:?}"
            );
        }
        for method in [
            BackendHttpMethod::Post,
            BackendHttpMethod::Put,
            BackendHttpMethod::Patch,
        ] {
            let mut bodied = request("x", "/a");
            bodied.method = method;
            bodied.body = Some(BackendBody::Json {
                bytes: b"{}".to_vec(),
            });
            assert_eq!(screen_request(&bodied), Ok(()), "method {method:?}");
        }
    }

    #[test]
    fn a_json_body_must_be_text() {
        let mut binary = request("x", "/a");
        binary.method = BackendHttpMethod::Post;
        binary.body = Some(BackendBody::Json {
            bytes: vec![0xff, 0xfe],
        });
        assert_eq!(
            reason(screen_request(&binary).unwrap_err()),
            "JSON body must be UTF-8"
        );
    }

    #[test]
    fn a_form_body_is_screened_like_a_query() {
        let mut form = request("x", "/a");
        form.method = BackendHttpMethod::Post;
        form.body = Some(BackendBody::Form {
            fields: vec![BackendQueryItem {
                name: "a=1&b".to_owned(),
                value: "v".to_owned(),
            }],
        });
        assert!(screen_request(&form).is_err());
    }

    #[test]
    fn a_response_keeps_only_allowlisted_headers() {
        let mut response = HostBackendResponse {
            status: 429,
            headers: vec![
                header("content-type", "application/json"),
                header("retry-after", "30"),
                header("set-cookie", "session=abc"),
                header("location", "https://internal.example.com/"),
                header("authorization", "Bearer secret"),
                header("www-authenticate", "Basic"),
            ],
            body: b"{}".to_vec(),
        };
        assert_eq!(screen_response(&mut response), Ok(()));
        assert_eq!(
            response.headers,
            vec![
                header("content-type", "application/json"),
                header("retry-after", "30"),
            ]
        );
    }

    #[test]
    fn a_response_header_carries_no_control_characters_and_is_bounded() {
        let mut response = HostBackendResponse {
            status: 200,
            headers: vec![
                header("content-type", "a\r\nX-Injected: 1"),
                header("retry-after", &"9".repeat(MAX_HEADER_VALUE_BYTES + 1)),
                header("link", "</next>; rel=\"next\""),
            ],
            body: Vec::new(),
        };
        assert_eq!(screen_response(&mut response), Ok(()));
        assert_eq!(
            response.headers,
            vec![header("link", "</next>; rel=\"next\"")]
        );
    }

    #[test]
    fn an_oversized_response_is_refused_rather_than_truncated() {
        let mut response = HostBackendResponse {
            status: 200,
            headers: Vec::new(),
            body: vec![0u8; MAX_RESPONSE_BYTES + 1],
        };
        assert_eq!(
            screen_response(&mut response),
            Err(HostBackendError::ResponseTooLarge)
        );
    }
}
