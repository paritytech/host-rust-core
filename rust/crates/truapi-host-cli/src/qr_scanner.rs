use std::fmt;
use std::process::Stdio;
use std::str;
use std::time::Duration;

use anyhow::{Context, Result as AnyResult};
use subtle::ConstantTimeEq;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::time;
use truapi_server::host_logic::sso::pairing::decode_pairing_deeplink;
use zeroize::Zeroize;

const MAX_FRAME_EDGE: u32 = 1280;
const MAX_FRAME_BODY: usize = 8 + MAX_FRAME_EDGE as usize * MAX_FRAME_EDGE as usize;
const MAX_REQUEST_HEAD: usize = 8 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);
const PAGE_TEMPLATE: &str = include_str!("scanner_page.html");

#[derive(Debug, PartialEq, Eq)]
pub(super) enum ScanOutcome {
    Deeplink(String),
    Cancelled,
}

pub(super) struct ScannerServer {
    listener: TcpListener,
    authority: String,
    token: SessionToken,
    csp_nonce: String,
}

impl ScannerServer {
    pub(super) async fn bind() -> AnyResult<Self> {
        Self::bind_with_credentials(random_hex(32)?, random_hex(16)?).await
    }

    async fn bind_with_credentials(token: String, csp_nonce: String) -> AnyResult<Self> {
        let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
            .await
            .context("bind QR scanner to loopback")?;
        let address = listener.local_addr().context("read QR scanner address")?;
        Ok(Self {
            listener,
            authority: address.to_string(),
            token: SessionToken(token),
            csp_nonce,
        })
    }

    pub(super) fn launch_url(&self) -> String {
        format!("http://{}/#{}", self.authority, self.token.expose())
    }

    #[cfg(test)]
    fn authority(&self) -> &str {
        &self.authority
    }

    pub(super) async fn scan(self) -> AnyResult<ScanOutcome> {
        loop {
            let (mut stream, peer) = self
                .listener
                .accept()
                .await
                .context("accept QR scanner request")?;
            if !peer.ip().is_loopback() {
                continue;
            }
            if let Some(outcome) = self.handle_connection(&mut stream).await? {
                return Ok(outcome);
            }
        }
    }

    async fn handle_connection(&self, stream: &mut TcpStream) -> AnyResult<Option<ScanOutcome>> {
        let request = match time::timeout(REQUEST_TIMEOUT, read_request(stream)).await {
            Ok(Ok(request)) => request,
            Ok(Err(ReadRequestError::Http(response))) => {
                write_response(stream, response, &[], &[]).await?;
                return Ok(None);
            }
            Ok(Err(ReadRequestError::Io(error))) => {
                return Err(error).context("read QR scanner request");
            }
            Err(_) => {
                write_response(stream, HttpStatus::RequestTimeout, &[], &[]).await?;
                return Ok(None);
            }
        };

        let result = match authorize_host(&request, &self.authority) {
            Ok(()) => match (request.method.as_str(), request.target.as_str()) {
                ("GET", "/") => self.serve_page(stream, &request).await?,
                ("POST", "/frame") => self.serve_frame(stream, request).await?,
                ("POST", "/cancel") => self.serve_cancel(stream, &request).await?,
                (_, "/" | "/frame" | "/cancel") => {
                    write_response(stream, HttpStatus::MethodNotAllowed, &[], &[]).await?;
                    None
                }
                _ => {
                    write_response(stream, HttpStatus::NotFound, &[], &[]).await?;
                    None
                }
            },
            Err(status) => {
                write_response(stream, status, &[], &[]).await?;
                None
            }
        };
        Ok(result)
    }

    async fn serve_page(
        &self,
        stream: &mut TcpStream,
        request: &HttpRequest,
    ) -> AnyResult<Option<ScanOutcome>> {
        if !request.body.is_empty() {
            write_response(stream, HttpStatus::BadRequest, &[], &[]).await?;
            return Ok(None);
        }
        match unique_header(&request.headers, "Origin") {
            Ok(Some(origin)) if origin != self.origin() => {
                write_response(stream, HttpStatus::Forbidden, &[], &[]).await?;
            }
            Err(()) => write_response(stream, HttpStatus::BadRequest, &[], &[]).await?,
            _ => {
                let page = render_page(&self.csp_nonce);
                let csp = format!(
                    "default-src 'none'; script-src 'nonce-{}'; style-src 'nonce-{}'; \
                     img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self'; \
                     worker-src 'none'; frame-src 'none'; frame-ancestors 'none'; base-uri 'none'; \
                     form-action 'none'; object-src 'none'",
                    self.csp_nonce, self.csp_nonce
                );
                let headers = [
                    ("Content-Type", "text/html; charset=utf-8"),
                    ("Cache-Control", "no-store"),
                    ("Content-Security-Policy", csp.as_str()),
                    (
                        "Permissions-Policy",
                        "camera=(self), display-capture=(self), microphone=()",
                    ),
                    ("Referrer-Policy", "no-referrer"),
                    ("X-Content-Type-Options", "nosniff"),
                    ("X-Frame-Options", "DENY"),
                    ("Cross-Origin-Opener-Policy", "same-origin"),
                    ("Cross-Origin-Resource-Policy", "same-origin"),
                ];
                write_response(stream, HttpStatus::Ok, &headers, page.as_bytes()).await?;
            }
        }
        Ok(None)
    }

    async fn serve_frame(
        &self,
        stream: &mut TcpStream,
        request: HttpRequest,
    ) -> AnyResult<Option<ScanOutcome>> {
        if let Err(status) = self.authorize_post(&request) {
            write_response(stream, status, &[], &[]).await?;
            return Ok(None);
        }
        match unique_header(&request.headers, "Content-Type") {
            Ok(Some("application/octet-stream")) => {}
            Ok(_) => {
                write_response(stream, HttpStatus::UnsupportedMediaType, &[], &[]).await?;
                return Ok(None);
            }
            Err(()) => {
                write_response(stream, HttpStatus::BadRequest, &[], &[]).await?;
                return Ok(None);
            }
        }
        let frame = match parse_frame_body(request.body) {
            Ok(frame) => frame,
            Err(_) => {
                write_response(stream, HttpStatus::BadRequest, &[], &[]).await?;
                return Ok(None);
            }
        };
        let outcome = tokio::task::spawn_blocking(move || {
            decode_frame(frame.width, frame.height, &frame.pixels)
        })
        .await
        .context("join QR decoder")?;
        match outcome {
            Ok(FrameOutcome::PairingDeeplink(deeplink)) => {
                write_response(stream, HttpStatus::Ok, &[], &[]).await?;
                Ok(Some(ScanOutcome::Deeplink(deeplink)))
            }
            Ok(FrameOutcome::MultiplePairingCodes) => {
                write_response(stream, HttpStatus::Conflict, &[], &[]).await?;
                Ok(None)
            }
            Ok(FrameOutcome::NotPairing) => {
                write_response(stream, HttpStatus::UnprocessableContent, &[], &[]).await?;
                Ok(None)
            }
            Ok(FrameOutcome::NoQr) => {
                write_response(stream, HttpStatus::NoContent, &[], &[]).await?;
                Ok(None)
            }
            Err(_) => {
                write_response(stream, HttpStatus::BadRequest, &[], &[]).await?;
                Ok(None)
            }
        }
    }

    async fn serve_cancel(
        &self,
        stream: &mut TcpStream,
        request: &HttpRequest,
    ) -> AnyResult<Option<ScanOutcome>> {
        if let Err(status) = self.authorize_post(request) {
            write_response(stream, status, &[], &[]).await?;
            return Ok(None);
        }
        if !request.body.is_empty() {
            write_response(stream, HttpStatus::BadRequest, &[], &[]).await?;
            return Ok(None);
        }
        write_response(stream, HttpStatus::NoContent, &[], &[]).await?;
        Ok(Some(ScanOutcome::Cancelled))
    }

    fn authorize_post(&self, request: &HttpRequest) -> Result<(), HttpStatus> {
        match unique_header(&request.headers, "Origin") {
            Ok(Some(origin)) if origin == self.origin() => {}
            Ok(_) => return Err(HttpStatus::Forbidden),
            Err(()) => return Err(HttpStatus::BadRequest),
        }
        match unique_header(&request.headers, "Authorization") {
            Ok(Some(value)) if self.token.matches_bearer(value) => Ok(()),
            Ok(_) => Err(HttpStatus::Unauthorized),
            Err(()) => Err(HttpStatus::BadRequest),
        }
    }

    fn origin(&self) -> String {
        format!("http://{}", self.authority)
    }
}

pub(super) async fn open_browser(url: &str) -> AnyResult<()> {
    let mut command = tokio::process::Command::new(browser_program()?);
    command
        .arg(url)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    let status = time::timeout(Duration::from_secs(10), command.status())
        .await
        .context("timed out opening the QR scanner in a browser")?
        .context("open the QR scanner in a browser")?;
    if !status.success() {
        anyhow::bail!("browser opener exited with {status}");
    }
    Ok(())
}

fn browser_program() -> AnyResult<&'static str> {
    #[cfg(target_os = "macos")]
    {
        Ok("open")
    }
    #[cfg(target_os = "linux")]
    {
        Ok("xdg-open")
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        anyhow::bail!("automatic browser opening is unsupported on this platform")
    }
}

struct SessionToken(String);

impl SessionToken {
    fn expose(&self) -> &str {
        &self.0
    }

    fn matches_bearer(&self, value: &str) -> bool {
        let Some(candidate) = value.strip_prefix("Bearer ") else {
            return false;
        };
        candidate.len() == self.0.len() && bool::from(candidate.as_bytes().ct_eq(self.0.as_bytes()))
    }
}

impl Drop for SessionToken {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

fn random_hex(bytes: usize) -> AnyResult<String> {
    let mut value = vec![0; bytes];
    getrandom::getrandom(&mut value)
        .map_err(|error| anyhow::anyhow!("generate QR scanner capability: {error}"))?;
    Ok(hex::encode(value))
}

#[derive(Debug, PartialEq, Eq)]
struct GrayFrame {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

#[derive(Debug, PartialEq, Eq)]
enum FrameOutcome {
    NoQr,
    NotPairing,
    MultiplePairingCodes,
    PairingDeeplink(String),
}

#[derive(Debug, PartialEq, Eq)]
enum FrameError {
    Header,
    Dimensions {
        width: u32,
        height: u32,
    },
    Length {
        width: u32,
        height: u32,
        actual: usize,
    },
}

fn parse_frame_body(body: Vec<u8>) -> Result<GrayFrame, FrameError> {
    let header: [u8; 8] = body
        .get(..8)
        .ok_or(FrameError::Header)?
        .try_into()
        .expect("the frame header is eight bytes");
    let width = u32::from_le_bytes(header[..4].try_into().expect("width is four bytes"));
    let height = u32::from_le_bytes(header[4..].try_into().expect("height is four bytes"));
    let pixels = body[8..].to_vec();
    if width == 0 || height == 0 || width > MAX_FRAME_EDGE || height > MAX_FRAME_EDGE {
        return Err(FrameError::Dimensions { width, height });
    }
    let expected = (width as usize)
        .checked_mul(height as usize)
        .ok_or(FrameError::Dimensions { width, height })?;
    if pixels.len() != expected {
        return Err(FrameError::Length {
            width,
            height,
            actual: pixels.len(),
        });
    }
    Ok(GrayFrame {
        width,
        height,
        pixels,
    })
}

fn render_page(nonce: &str) -> String {
    PAGE_TEMPLATE.replace("__CSP_NONCE__", nonce)
}

fn decode_frame(width: u32, height: u32, pixels: &[u8]) -> Result<FrameOutcome, FrameError> {
    if width == 0 || height == 0 || width > MAX_FRAME_EDGE || height > MAX_FRAME_EDGE {
        return Err(FrameError::Dimensions { width, height });
    }
    let expected = (width as usize)
        .checked_mul(height as usize)
        .ok_or(FrameError::Dimensions { width, height })?;
    if pixels.len() != expected {
        return Err(FrameError::Length {
            width,
            height,
            actual: pixels.len(),
        });
    }

    let width = width as usize;
    let height = height as usize;
    let mut image = rqrr::PreparedImage::prepare_from_greyscale(width, height, |column, row| {
        pixels[row * width + column]
    });
    let mut decoded_any = false;
    let mut pairing_deeplinks = Vec::new();
    for grid in image.detect_grids() {
        let Ok((_, payload)) = grid.decode() else {
            continue;
        };
        decoded_any = true;
        if payload.starts_with("polkadotapp://pair?handshake=")
            && decode_pairing_deeplink(&payload).is_ok()
            && !pairing_deeplinks.contains(&payload)
        {
            pairing_deeplinks.push(payload);
        }
    }

    Ok(match pairing_deeplinks.len() {
        0 if decoded_any => FrameOutcome::NotPairing,
        0 => FrameOutcome::NoQr,
        1 => FrameOutcome::PairingDeeplink(pairing_deeplinks.pop().expect("one deeplink")),
        _ => FrameOutcome::MultiplePairingCodes,
    })
}

struct HttpRequest {
    method: String,
    target: String,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

enum ReadRequestError {
    Http(HttpStatus),
    Io(std::io::Error),
}

impl From<std::io::Error> for ReadRequestError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}

async fn read_request(stream: &mut TcpStream) -> Result<HttpRequest, ReadRequestError> {
    let mut bytes = Vec::with_capacity(1024);
    let head_end = loop {
        if let Some(offset) = bytes.windows(4).position(|window| window == b"\r\n\r\n") {
            break offset + 4;
        }
        if bytes.len() >= MAX_REQUEST_HEAD {
            return Err(ReadRequestError::Http(
                HttpStatus::RequestHeaderFieldsTooLarge,
            ));
        }
        let mut chunk = [0; 1024];
        let read = stream.read(&mut chunk).await?;
        if read == 0 {
            return Err(ReadRequestError::Http(HttpStatus::BadRequest));
        }
        bytes.extend_from_slice(&chunk[..read]);
        if bytes.len() > MAX_REQUEST_HEAD + MAX_FRAME_BODY {
            return Err(ReadRequestError::Http(HttpStatus::PayloadTooLarge));
        }
    };

    let mut parsed_headers = [httparse::EMPTY_HEADER; 32];
    let mut parsed = httparse::Request::new(&mut parsed_headers);
    let parsed_end = match parsed.parse(&bytes[..head_end]) {
        Ok(httparse::Status::Complete(end)) => end,
        _ => return Err(ReadRequestError::Http(HttpStatus::BadRequest)),
    };
    if parsed_end != head_end || parsed.version != Some(1) {
        return Err(ReadRequestError::Http(HttpStatus::BadRequest));
    }
    let method = parsed
        .method
        .ok_or(ReadRequestError::Http(HttpStatus::BadRequest))?
        .to_string();
    let target = parsed
        .path
        .ok_or(ReadRequestError::Http(HttpStatus::BadRequest))?
        .to_string();
    let headers = parsed
        .headers
        .iter()
        .map(|header| {
            str::from_utf8(header.value)
                .map(|value| (header.name.to_string(), value.to_string()))
                .map_err(|_| ReadRequestError::Http(HttpStatus::BadRequest))
        })
        .collect::<Result<Vec<_>, _>>()?;

    if headers
        .iter()
        .any(|(name, _)| name.eq_ignore_ascii_case("Transfer-Encoding"))
    {
        return Err(ReadRequestError::Http(HttpStatus::BadRequest));
    }
    let content_length = match unique_header(&headers, "Content-Length") {
        Ok(Some(value)) => value
            .parse::<usize>()
            .map_err(|_| ReadRequestError::Http(HttpStatus::BadRequest))?,
        Ok(None) => 0,
        Err(()) => return Err(ReadRequestError::Http(HttpStatus::BadRequest)),
    };
    if content_length > MAX_FRAME_BODY {
        return Err(ReadRequestError::Http(HttpStatus::PayloadTooLarge));
    }
    let body_prefix = &bytes[head_end..];
    if body_prefix.len() > content_length {
        return Err(ReadRequestError::Http(HttpStatus::BadRequest));
    }
    let mut body = Vec::with_capacity(content_length);
    body.extend_from_slice(body_prefix);
    while body.len() < content_length {
        let remaining = content_length - body.len();
        let mut chunk = vec![0; remaining.min(8192)];
        let read = stream.read(&mut chunk).await?;
        if read == 0 {
            return Err(ReadRequestError::Http(HttpStatus::BadRequest));
        }
        body.extend_from_slice(&chunk[..read]);
    }

    Ok(HttpRequest {
        method,
        target,
        headers,
        body,
    })
}

fn unique_header<'a>(headers: &'a [(String, String)], name: &str) -> Result<Option<&'a str>, ()> {
    let mut values = headers
        .iter()
        .filter(|(current, _)| current.eq_ignore_ascii_case(name))
        .map(|(_, value)| value.as_str());
    let first = values.next();
    if values.next().is_some() {
        return Err(());
    }
    Ok(first)
}

fn authorize_host(request: &HttpRequest, authority: &str) -> Result<(), HttpStatus> {
    match unique_header(&request.headers, "Host") {
        Ok(Some(host)) if host == authority => Ok(()),
        Ok(_) => Err(HttpStatus::MisdirectedRequest),
        Err(()) => Err(HttpStatus::BadRequest),
    }
}

#[derive(Clone, Copy)]
enum HttpStatus {
    Ok,
    NoContent,
    BadRequest,
    Unauthorized,
    Forbidden,
    NotFound,
    MethodNotAllowed,
    Conflict,
    PayloadTooLarge,
    UnsupportedMediaType,
    UnprocessableContent,
    MisdirectedRequest,
    RequestTimeout,
    RequestHeaderFieldsTooLarge,
}

impl HttpStatus {
    const fn code(self) -> u16 {
        match self {
            Self::Ok => 200,
            Self::NoContent => 204,
            Self::BadRequest => 400,
            Self::Unauthorized => 401,
            Self::Forbidden => 403,
            Self::NotFound => 404,
            Self::MethodNotAllowed => 405,
            Self::Conflict => 409,
            Self::PayloadTooLarge => 413,
            Self::UnsupportedMediaType => 415,
            Self::UnprocessableContent => 422,
            Self::MisdirectedRequest => 421,
            Self::RequestTimeout => 408,
            Self::RequestHeaderFieldsTooLarge => 431,
        }
    }

    const fn reason(self) -> &'static str {
        match self {
            Self::Ok => "OK",
            Self::NoContent => "No Content",
            Self::BadRequest => "Bad Request",
            Self::Unauthorized => "Unauthorized",
            Self::Forbidden => "Forbidden",
            Self::NotFound => "Not Found",
            Self::MethodNotAllowed => "Method Not Allowed",
            Self::Conflict => "Conflict",
            Self::PayloadTooLarge => "Payload Too Large",
            Self::UnsupportedMediaType => "Unsupported Media Type",
            Self::UnprocessableContent => "Unprocessable Content",
            Self::MisdirectedRequest => "Misdirected Request",
            Self::RequestTimeout => "Request Timeout",
            Self::RequestHeaderFieldsTooLarge => "Request Header Fields Too Large",
        }
    }
}

impl fmt::Display for HttpStatus {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{} {}", self.code(), self.reason())
    }
}

async fn write_response(
    stream: &mut TcpStream,
    status: HttpStatus,
    headers: &[(&str, &str)],
    body: &[u8],
) -> AnyResult<()> {
    let mut response = format!(
        "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n",
        body.len()
    )
    .into_bytes();
    for (name, value) in headers {
        response.extend_from_slice(name.as_bytes());
        response.extend_from_slice(b": ");
        response.extend_from_slice(value.as_bytes());
        response.extend_from_slice(b"\r\n");
    }
    response.extend_from_slice(b"\r\n");
    response.extend_from_slice(body);
    stream
        .write_all(&response)
        .await
        .context("write QR scanner response")?;
    stream
        .shutdown()
        .await
        .context("finish QR scanner response")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::Encode;
    use qrcode::{Color, QrCode};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpStream;
    use truapi_server::host_logic::sso::pairing::{
        VersionedHandshakeProposal,
        v2::{Device, Proposal},
    };

    use super::*;

    #[test]
    fn decodes_a_complete_pairing_proposal_from_grayscale_pixels() {
        let deeplink = pairing_deeplink();
        let frame = qr_frame(&deeplink);

        assert_eq!(
            decode_frame(frame.width, frame.height, &frame.pixels),
            Ok(FrameOutcome::PairingDeeplink(deeplink))
        );
    }

    #[test]
    fn distinguishes_an_unrelated_qr_from_a_frame_without_a_qr() {
        let unrelated = qr_frame("https://example.com/not-a-pairing-code");
        let blank = GrayFrame {
            width: 320,
            height: 240,
            pixels: vec![255; 320 * 240],
        };

        assert_eq!(
            (
                decode_frame(unrelated.width, unrelated.height, &unrelated.pixels),
                decode_frame(blank.width, blank.height, &blank.pixels),
            ),
            (Ok(FrameOutcome::NotPairing), Ok(FrameOutcome::NoQr))
        );
    }

    #[test]
    fn accepts_one_pairing_code_among_unrelated_codes_and_rejects_ambiguous_frames() {
        let first = pairing_deeplink_for(1);
        let second = pairing_deeplink_for(9);
        let unrelated = qr_frame("https://example.com/not-a-pairing-code");
        let first_code = qr_frame(&first);
        let second_code = qr_frame(&second);

        let pairing_and_unrelated = side_by_side(&first_code, &unrelated);
        let unrelated_and_pairing = side_by_side(&unrelated, &first_code);
        let two_pairing_codes = side_by_side(&first_code, &second_code);
        let duplicate_pairing_code = side_by_side(&first_code, &first_code);

        assert_eq!(
            (
                decode_frame(
                    pairing_and_unrelated.width,
                    pairing_and_unrelated.height,
                    &pairing_and_unrelated.pixels,
                ),
                decode_frame(
                    unrelated_and_pairing.width,
                    unrelated_and_pairing.height,
                    &unrelated_and_pairing.pixels,
                ),
                decode_frame(
                    two_pairing_codes.width,
                    two_pairing_codes.height,
                    &two_pairing_codes.pixels,
                ),
                decode_frame(
                    duplicate_pairing_code.width,
                    duplicate_pairing_code.height,
                    &duplicate_pairing_code.pixels,
                ),
            ),
            (
                Ok(FrameOutcome::PairingDeeplink(first.clone())),
                Ok(FrameOutcome::PairingDeeplink(first.clone())),
                Ok(FrameOutcome::MultiplePairingCodes),
                Ok(FrameOutcome::PairingDeeplink(first)),
            )
        );
    }

    #[test]
    fn rejects_inconsistent_or_oversized_grayscale_frames_before_decoding() {
        assert_eq!(
            (
                decode_frame(2, 2, &[0; 3]),
                decode_frame(MAX_FRAME_EDGE + 1, 1, &[]),
            ),
            (
                Err(FrameError::Length {
                    width: 2,
                    height: 2,
                    actual: 3,
                }),
                Err(FrameError::Dimensions {
                    width: MAX_FRAME_EDGE + 1,
                    height: 1,
                }),
            )
        );
    }

    #[test]
    fn parses_the_bounded_binary_frame_contract_used_by_the_scanner_page() {
        let mut body = Vec::from([2, 0, 0, 0, 2, 0, 0, 0]);
        body.extend_from_slice(&[0, 85, 170, 255]);

        assert_eq!(
            (
                parse_frame_body(body),
                parse_frame_body(vec![2, 0, 0, 0, 2, 0, 0, 0, 0]),
            ),
            (
                Ok(GrayFrame {
                    width: 2,
                    height: 2,
                    pixels: vec![0, 85, 170, 255],
                }),
                Err(FrameError::Length {
                    width: 2,
                    height: 2,
                    actual: 1,
                }),
            )
        );
    }

    #[test]
    fn bundled_page_exposes_every_scan_source_without_remote_assets() {
        let page = render_page("fixture-nonce");

        assert!(page.contains(r#"id="display-source""#));
        assert!(page.contains(r#"id="camera-source""#));
        assert!(page.contains(r#"id="image-file""#));
        assert!(page.contains(r#"id="drop-zone""#));
        assert!(page.contains("getDisplayMedia"));
        assert!(page.contains("getUserMedia"));
        assert!(page.contains("clipboardData"));
        assert!(page.contains(r#"nonce="fixture-nonce""#));
        assert!(!page.contains("__CSP_NONCE__"));
        assert!(!page.contains("https://"));
        assert!(!page.contains("http://"));
    }

    #[tokio::test]
    async fn scanner_server_is_loopback_capability_scoped_and_one_shot() {
        let token = "11".repeat(32);
        let scanner = ScannerServer::bind_with_credentials(token.clone(), "fixture-nonce".into())
            .await
            .expect("bind scanner");
        let authority = scanner.authority().to_string();
        assert!(scanner.launch_url().ends_with(&format!("/#{token}")));
        let scan = tokio::spawn(scanner.scan());

        let page = request(
            &authority,
            &format!("GET / HTTP/1.1\r\nHost: {authority}\r\n\r\n"),
        )
        .await;
        assert!(page.starts_with("HTTP/1.1 200 OK\r\n"));
        assert!(page.contains("Content-Security-Policy: default-src 'none';"));
        assert!(
            page.contains(
                "Permissions-Policy: camera=(self), display-capture=(self), microphone=()"
            )
        );
        assert!(!page.contains(&token));

        let frame = frame_body(qr_frame("https://example.com/not-pairing"));
        let foreign = post_frame(&authority, &token, "http://example.com", &frame).await;
        assert!(foreign.starts_with("HTTP/1.1 403 Forbidden\r\n"));

        let missing_token = request(
            &authority,
            &format!(
                "POST /frame HTTP/1.1\r\nHost: {authority}\r\nOrigin: http://{authority}\r\nContent-Type: application/octet-stream\r\nContent-Length: 0\r\n\r\n"
            ),
        )
        .await;
        assert!(missing_token.starts_with("HTTP/1.1 401 Unauthorized\r\n"));

        let unrelated =
            post_frame(&authority, &token, &format!("http://{authority}"), &frame).await;
        assert!(unrelated.starts_with("HTTP/1.1 422 Unprocessable Content\r\n"));

        let deeplink = pairing_deeplink();
        let valid = frame_body(qr_frame(&deeplink));
        let accepted = post_frame(&authority, &token, &format!("http://{authority}"), &valid).await;
        assert!(accepted.starts_with("HTTP/1.1 200 OK\r\n"));
        assert_eq!(
            scan.await.expect("scanner task").expect("scanner result"),
            ScanOutcome::Deeplink(deeplink)
        );
        assert!(TcpStream::connect(&authority).await.is_err());
    }

    #[tokio::test]
    async fn page_cancel_ends_the_scan_without_a_pairing_result() {
        let token = "22".repeat(32);
        let scanner = ScannerServer::bind_with_credentials(token.clone(), "fixture-nonce".into())
            .await
            .expect("bind scanner");
        let authority = scanner.authority().to_string();
        let scan = tokio::spawn(scanner.scan());

        let response = request(
            &authority,
            &format!(
                "POST /cancel HTTP/1.1\r\nHost: {authority}\r\nOrigin: http://{authority}\r\nAuthorization: Bearer {token}\r\nContent-Length: 0\r\n\r\n"
            ),
        )
        .await;

        assert!(response.starts_with("HTTP/1.1 204 No Content\r\n"));
        assert_eq!(
            scan.await.expect("scanner task").expect("scanner result"),
            ScanOutcome::Cancelled
        );
    }

    fn pairing_deeplink() -> String {
        pairing_deeplink_for(1)
    }

    fn pairing_deeplink_for(account_byte: u8) -> String {
        let proposal = VersionedHandshakeProposal::V2(Proposal {
            device: Device {
                statement_account_id: [account_byte; 32],
                encryption_public_key: [account_byte.wrapping_add(1); 32],
            },
            metadata: Vec::new(),
        });
        format!(
            "polkadotapp://pair?handshake={}",
            hex::encode(proposal.encode())
        )
    }

    fn qr_frame(payload: &str) -> GrayFrame {
        const QUIET_ZONE: usize = 4;
        const SCALE: usize = 8;

        let code = QrCode::new(payload.as_bytes()).expect("fixture QR encodes");
        let modules = code.to_colors();
        let module_width = code.width();
        let width = (module_width + QUIET_ZONE * 2) * SCALE;
        let mut pixels = vec![255; width * width];
        for row in 0..module_width {
            for column in 0..module_width {
                if modules[row * module_width + column] != Color::Dark {
                    continue;
                }
                let output_row = (row + QUIET_ZONE) * SCALE;
                let output_column = (column + QUIET_ZONE) * SCALE;
                for y in output_row..output_row + SCALE {
                    pixels[y * width + output_column..y * width + output_column + SCALE].fill(0);
                }
            }
        }
        GrayFrame {
            width: width as u32,
            height: width as u32,
            pixels,
        }
    }

    fn side_by_side(left: &GrayFrame, right: &GrayFrame) -> GrayFrame {
        const GAP: usize = 32;

        let left_width = left.width as usize;
        let right_width = right.width as usize;
        let width = left_width + GAP + right_width;
        let height = left.height.max(right.height) as usize;
        let mut pixels = vec![255; width * height];
        for (source, offset) in [(left, 0), (right, left_width + GAP)] {
            let source_width = source.width as usize;
            for row in 0..source.height as usize {
                pixels[row * width + offset..row * width + offset + source_width]
                    .copy_from_slice(&source.pixels[row * source_width..(row + 1) * source_width]);
            }
        }
        GrayFrame {
            width: width as u32,
            height: height as u32,
            pixels,
        }
    }

    fn frame_body(frame: GrayFrame) -> Vec<u8> {
        let mut body = Vec::with_capacity(8 + frame.pixels.len());
        body.extend_from_slice(&frame.width.to_le_bytes());
        body.extend_from_slice(&frame.height.to_le_bytes());
        body.extend_from_slice(&frame.pixels);
        body
    }

    async fn post_frame(authority: &str, token: &str, origin: &str, body: &[u8]) -> String {
        let mut request = format!(
            "POST /frame HTTP/1.1\r\nHost: {authority}\r\nOrigin: {origin}\r\nAuthorization: Bearer {token}\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\n\r\n",
            body.len()
        )
        .into_bytes();
        request.extend_from_slice(body);
        request_bytes(authority, &request).await
    }

    async fn request(authority: &str, request: &str) -> String {
        request_bytes(authority, request.as_bytes()).await
    }

    async fn request_bytes(authority: &str, request: &[u8]) -> String {
        let mut stream = TcpStream::connect(authority)
            .await
            .expect("connect scanner");
        stream.write_all(request).await.expect("write request");
        stream.shutdown().await.expect("finish request");
        let mut response = Vec::new();
        stream
            .read_to_end(&mut response)
            .await
            .expect("read response");
        String::from_utf8_lossy(&response).into_owned()
    }
}
