//! Backend tunnel for the CLI host.
//!
//! The registry is read from `TRUAPI_BACKENDS` as `id=base_url[,token]` entries
//! separated by `;`. With nothing configured the host starts a loopback echo
//! server and registers it as `echo`, so the generated example and the battery
//! have a backend to call headlessly.

use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;

use futures::StreamExt;

use reqwest::Url;
use reqwest::redirect::Policy;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use truapi::latest::{
    BackendBody, BackendHeader, BackendHttpMethod, HostBackendError, HostBackendListResponse,
    HostBackendRequest, HostBackendResponse,
};
use truapi_platform::{BackendHost, ProductContext, async_trait};

/// Largest response body this host reads.
const MAX_RESPONSE_BYTES: usize = 1024 * 1024;

/// How long one backend call may take.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// Header naming the calling product to the backend.
const PRODUCT_HEADER: &str = "X-Polkadot-Product";

/// Response headers this host passes back.
const ALLOWED_RESPONSE_HEADERS: &[&str] = &[
    "content-type",
    "retry-after",
    "link",
    "x-ratelimit-limit",
    "x-ratelimit-remaining",
    "x-ratelimit-reset",
];

/// One registered backend: where it lives and what authenticates the host to it.
struct BackendEntry {
    base: Url,
    token: Option<String>,
}

/// Backend tunnel backed by `reqwest`.
pub struct CliBackendHost {
    registry: BTreeMap<String, BackendEntry>,
    client: reqwest::Client,
}

fn transport(reason: impl std::fmt::Display) -> HostBackendError {
    HostBackendError::Transport {
        reason: reason.to_string(),
    }
}

/// Parse `id=base[,token];id2=base2` into a registry. A base carrying a query
/// or fragment is dropped: a path set on it would land inside the query.
fn parse_registry(spec: &str) -> BTreeMap<String, BackendEntry> {
    spec.split(';')
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
        .filter_map(|entry| {
            let (id, rest) = entry.split_once('=')?;
            let (base, token) = match rest.split_once(',') {
                Some((base, token)) => (base, Some(token.trim().to_string())),
                None => (rest, None),
            };
            let base = Url::parse(base.trim()).ok()?;
            if base.query().is_some() || base.fragment().is_some() {
                return None;
            }
            Some((
                id.trim().to_string(),
                BackendEntry {
                    base,
                    token: token.filter(|token| !token.is_empty()),
                },
            ))
        })
        .collect()
}

impl CliBackendHost {
    /// Build a backend host from `TRUAPI_BACKENDS`, falling back to a loopback
    /// echo backend registered as `echo`.
    pub fn from_env() -> Arc<Self> {
        let mut registry = std::env::var("TRUAPI_BACKENDS")
            .ok()
            .map(|spec| parse_registry(&spec))
            .unwrap_or_default();

        if !registry.contains_key("echo")
            && let Some(base) = spawn_echo_backend()
        {
            registry.insert("echo".to_string(), BackendEntry { base, token: None });
        }

        Arc::new(Self {
            registry,
            // Not `unwrap_or_default`: the default client follows redirects,
            // so a silent fallback would drop an obligation this host owes.
            client: reqwest::Client::builder()
                .redirect(Policy::none())
                .timeout(REQUEST_TIMEOUT)
                .build()
                .expect("backend HTTP client builds"),
        })
    }

    /// Join a screened path onto a registered base without string concatenation.
    fn url_for(entry: &BackendEntry, request: &HostBackendRequest) -> Url {
        let mut url = entry.base.clone();
        let prefix = entry.base.path().trim_end_matches('/');
        url.set_path(&format!("{prefix}{}", request.path));
        {
            let mut pairs = url.query_pairs_mut();
            for item in &request.query {
                pairs.append_pair(&item.name, &item.value);
            }
        }
        if request.query.is_empty() {
            url.set_query(None);
        }
        url
    }
}

fn method_of(method: BackendHttpMethod) -> reqwest::Method {
    match method {
        BackendHttpMethod::Get => reqwest::Method::GET,
        BackendHttpMethod::Head => reqwest::Method::HEAD,
        BackendHttpMethod::Post => reqwest::Method::POST,
        BackendHttpMethod::Put => reqwest::Method::PUT,
        BackendHttpMethod::Patch => reqwest::Method::PATCH,
        BackendHttpMethod::Delete => reqwest::Method::DELETE,
    }
}

#[async_trait]
impl BackendHost for CliBackendHost {
    async fn backend_request(
        &self,
        product: &ProductContext,
        request: HostBackendRequest,
    ) -> Result<HostBackendResponse, HostBackendError> {
        let entry = self
            .registry
            .get(&request.backend)
            .ok_or(HostBackendError::UnknownBackend)?;

        let mut call = self
            .client
            .request(method_of(request.method), Self::url_for(entry, &request))
            .header(PRODUCT_HEADER, product.product_id.clone());

        if let Some(token) = &entry.token {
            call = call.bearer_auth(token);
        }

        call = match request.body {
            Some(BackendBody::Json { bytes }) => {
                call.header("Content-Type", "application/json").body(bytes)
            }
            Some(BackendBody::Form { fields }) => {
                let pairs: Vec<(String, String)> = fields
                    .into_iter()
                    .map(|item| (item.name, item.value))
                    .collect();
                call.form(&pairs)
            }
            None => call,
        };

        let response = call.send().await.map_err(transport)?;
        let status = response.status().as_u16();
        let headers = response
            .headers()
            .iter()
            .filter(|(name, _)| ALLOWED_RESPONSE_HEADERS.contains(&name.as_str()))
            .filter_map(|(name, value)| {
                Some(BackendHeader {
                    name: name.as_str().to_string(),
                    value: value.to_str().ok()?.to_string(),
                })
            })
            .collect();

        // A declared length over the cap is refused before a byte is read, and
        // the streamed accumulation bounds an undeclared one, so the cap holds
        // whether or not the backend is honest about its size.
        if response
            .content_length()
            .is_some_and(|length| length > MAX_RESPONSE_BYTES as u64)
        {
            return Err(HostBackendError::ResponseTooLarge);
        }

        let mut body = Vec::new();
        let mut chunks = response.bytes_stream();
        while let Some(chunk) = chunks.next().await {
            let chunk = chunk.map_err(transport)?;
            if body.len() + chunk.len() > MAX_RESPONSE_BYTES {
                return Err(HostBackendError::ResponseTooLarge);
            }
            body.extend_from_slice(&chunk);
        }

        Ok(HostBackendResponse {
            status,
            headers,
            body,
        })
    }

    async fn backends(
        &self,
        _product: &ProductContext,
    ) -> Result<HostBackendListResponse, truapi::latest::GenericError> {
        Ok(HostBackendListResponse {
            backends: self.registry.keys().cloned().collect(),
        })
    }
}

/// Start a loopback backend that echoes the request line back.
fn spawn_echo_backend() -> Option<Url> {
    // Bound synchronously so a host can be built outside async context.
    let handle = tokio::runtime::Handle::try_current().ok()?;
    let listener = std::net::TcpListener::bind("127.0.0.1:0").ok()?;
    let address = listener.local_addr().ok()?;
    listener.set_nonblocking(true).ok()?;
    handle.spawn(async move {
        let Ok(listener) = TcpListener::from_std(listener) else {
            return;
        };
        while let Ok((mut stream, _)) = listener.accept().await {
            tokio::spawn(async move {
                let mut buffer = [0u8; 8192];
                let read = stream.read(&mut buffer).await.unwrap_or(0);
                let head = String::from_utf8_lossy(&buffer[..read]);
                let request_line = head.lines().next().unwrap_or_default().to_string();
                let body = format!("{{\"echo\":\"{}\"}}", request_line.replace('"', "'"));
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                let _ = stream.write_all(response.as_bytes()).await;
                let _ = stream.shutdown().await;
            });
        }
    });
    Url::parse(&format!("http://{address}/")).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(path: &str) -> HostBackendRequest {
        HostBackendRequest {
            backend: "echo".to_string(),
            method: BackendHttpMethod::Get,
            path: path.to_string(),
            query: Vec::new(),
            body: None,
        }
    }

    #[test]
    fn a_base_with_a_query_or_fragment_is_not_registered() {
        assert!(parse_registry("a=https://example.com/v1?key=abc").is_empty());
        assert!(parse_registry("a=https://example.com/v1#x").is_empty());
        assert_eq!(parse_registry("a=https://example.com/v1").len(), 1);
    }

    #[test]
    fn a_registry_entry_takes_an_optional_token() {
        let registry = parse_registry("a=https://example.com,secret; b=https://other.example");
        assert_eq!(registry["a"].token.as_deref(), Some("secret"));
        assert_eq!(registry["b"].token, None);
    }

    #[test]
    fn a_path_is_set_on_the_base_rather_than_appended() {
        let entry = BackendEntry {
            base: Url::parse("https://example.com/v1/").expect("base parses"),
            token: None,
        };
        assert_eq!(
            CliBackendHost::url_for(&entry, &request("/providers")).as_str(),
            "https://example.com/v1/providers"
        );
    }

    #[test]
    fn query_parameters_are_encoded_by_the_host() {
        let entry = BackendEntry {
            base: Url::parse("https://example.com").expect("base parses"),
            token: None,
        };
        let mut with_query = request("/a");
        with_query.query = vec![truapi::latest::BackendQueryItem {
            name: "q".to_string(),
            value: "a&b=c#d".to_string(),
        }];
        assert_eq!(
            CliBackendHost::url_for(&entry, &with_query).as_str(),
            "https://example.com/a?q=a%26b%3Dc%23d"
        );
    }
}
