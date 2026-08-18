#![allow(
    clippy::double_must_use,
    reason = "async-trait generates must_use futures for async trait methods"
)]

//! Capability traits a TrUAPI host must implement.
//!
//! Each trait covers a single OS-primitive surface the Rust core cannot reach
//! from its own process (key-value persistence, URL launching, push
//! notifications, permission UI, chain RPC, host-selected preimage backends).
//! Account management, signing, and statement-store protocol flows live in the
//! Rust core itself and are not part of this trait set.
//!
//! Async capability traits use `async_trait` so the combined [`Platform`]
//! surface can be used as a trait object by the runtime.

use futures::stream::BoxStream;
use parity_scale_codec::{Decode, Encode};
use unicode_normalization::UnicodeNormalization;

pub use async_trait::async_trait;

#[cfg(feature = "uniffi")]
uniffi::setup_scaffolding!();

#[cfg(feature = "uniffi")]
uniffi::use_remote_type!(truapi::Bytes32);

use truapi::Bytes32;
use truapi::latest::{
    AllocatableResource, ChainIdentifier, GenericError, HostChatCreateRoomError,
    HostChatCreateRoomRequest, HostChatCreateRoomResponse, HostChatListSubscribeItem,
    HostChatPostMessageError, HostChatPostMessageRequest, HostChatPostMessageResponse,
    HostChatRegisterBotError, HostChatRegisterBotRequest, HostChatRegisterBotResponse,
    HostDevicePermissionRequest, HostDevicePermissionResponse, HostFeatureSupportedRequest,
    HostFeatureSupportedResponse, HostLocalStorageReadError, HostNavigateToError,
    HostPushNotificationRequest, HostPushNotificationResponse, HostSignPayloadRequest,
    HostSignPayloadWithLegacyAccountRequest, HostSignRawRequest,
    HostSignRawWithLegacyAccountRequest, HostThemeSubscribeItem, LegacyAccountTxPayload,
    NotificationId, ProductAccountId, ProductAccountTxPayload, ProductProofContext,
    RemotePermission, RemotePermissionRequest, RemotePermissionResponse, RingLocation,
};
use truapi::v01::HostAccountSignVrfRequest;
use url::Url;

/// Role-neutral runtime configuration supplied by the embedding host.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostRuntimeConfig {
    /// Host metadata.
    pub host_info: HostInfo,
    /// Platform metadata.
    pub platform_info: PlatformInfo,
}

/// Pairing-host runtime configuration supplied by the embedding host.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingHostConfig {
    /// Host identity shown to the signing host during pairing.
    ///
    /// Host-spec B.1.3 defines the host metadata consumed by the signing host:
    /// <https://github.com/paritytech/host-spec/blob/adb3989208ae1c2107dbf0159611353e6989422c/spec/B-inter-host.md?plain=1#L48-L60>
    pub host: HostRuntimeConfig,
    /// People-chain genesis hash used for statement-store SSO.
    pub people_chain_genesis_hash: [u8; 32],
    /// Bulletin-chain genesis hash used for in-core preimage submission.
    pub bulletin_chain_genesis_hash: [u8; 32],
    /// Deeplink URI scheme used in pairing QR payloads, without `://`.
    ///
    /// Host-spec L.2-L.3 define the `polkadotapp://pair` route and construction
    /// rules:
    /// <https://github.com/paritytech/host-spec/blob/adb3989208ae1c2107dbf0159611353e6989422c/spec/L-url-schemes.md?plain=1#L17-L33>
    pub pairing_deeplink_scheme: String,
}

/// Signing-host runtime configuration supplied by the embedding host.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SigningHostConfig {
    /// Host identity. Not read by the local-signing paths yet; retained for
    /// parity with [`PairingHostConfig`] and for the future signer-side SSO
    /// responder, which advertises host identity in handshake responses.
    pub host: HostRuntimeConfig,
    /// People-chain genesis hash used for statement-store product calls.
    pub people_chain_genesis_hash: [u8; 32],
    /// Bulletin-chain genesis hash used for in-core preimage submission.
    pub bulletin_chain_genesis_hash: [u8; 32],
}

/// Product identity attached to one product-facing TrUAPI connection.
///
/// A host may create multiple product runtimes from the same long-lived host
/// runtime, each with its own product context.
#[non_exhaustive]
// `Decode` is hand-written below so decoding cannot bypass the validating
// constructor. Not a doc comment: wire-type docs are emitted into the generated
// host API, and this is a Rust-side implementation note.
#[derive(Debug, Clone, PartialEq, Eq, Encode)]
pub struct ProductContext {
    /// Product identifier used for account derivation and product-scoped
    /// storage/permission namespaces.
    ///
    /// Host-spec C.7 defines accepted product id forms:
    /// <https://github.com/paritytech/host-spec/blob/adb3989208ae1c2107dbf0159611353e6989422c/spec/C-account-derivation.md?plain=1#L109-L128>
    pub product_id: String,
    /// Trusted kind of executable attached to this connection by the host.
    pub execution_kind: ProductExecutionKind,
}

/// Trusted kind of product executable attached to a TrUAPI connection.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum ProductExecutionKind {
    /// Visible single-page application entrypoint such as `app/index.html`.
    #[default]
    Spa,
    /// Headless worker executable that provides the Chat modality.
    Chat,
}

/// Host metadata.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostInfo {
    /// Host name.
    pub name: String,
    /// Optional absolute HTTPS host icon URL.
    pub icon: Option<String>,
    /// Optional host version.
    pub version: Option<String>,
}

/// Platform metadata.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PlatformInfo {
    /// Optional platform/browser name.
    pub kind: Option<String>,
    /// Optional platform/browser version.
    pub version: Option<String>,
}

impl HostRuntimeConfig {
    /// Build a role-neutral host runtime config, validating fields whose
    /// representation cannot be made invalid by Rust types alone.
    pub fn new(
        host_info: HostInfo,
        platform_info: PlatformInfo,
    ) -> Result<Self, RuntimeConfigValidationError> {
        require_non_empty("host_info.name", &host_info.name)?;
        if let Some(icon) = &host_info.icon {
            let parsed = Url::parse(icon)
                .map_err(|source| RuntimeConfigValidationError::InvalidHostIcon { source })?;
            if parsed.scheme() != "https" {
                return Err(RuntimeConfigValidationError::InsecureHostIcon {
                    scheme: parsed.scheme().to_string(),
                });
            }
        }
        Ok(Self {
            host_info,
            platform_info,
        })
    }
}

impl PairingHostConfig {
    /// Build a pairing-host runtime config, validating fields whose
    /// representation cannot be made invalid by Rust types alone.
    pub fn new(
        host_info: HostInfo,
        platform_info: PlatformInfo,
        people_chain_genesis_hash: [u8; 32],
        bulletin_chain_genesis_hash: [u8; 32],
        pairing_deeplink_scheme: String,
    ) -> Result<Self, RuntimeConfigValidationError> {
        require_non_empty("pairing_deeplink_scheme", &pairing_deeplink_scheme)?;
        if pairing_deeplink_scheme.contains("://") {
            return Err(RuntimeConfigValidationError::InvalidDeeplinkScheme {
                scheme: pairing_deeplink_scheme,
            });
        }
        let config = Self {
            host: HostRuntimeConfig::new(host_info, platform_info)?,
            people_chain_genesis_hash,
            bulletin_chain_genesis_hash,
            pairing_deeplink_scheme,
        };
        Ok(config)
    }
}

impl SigningHostConfig {
    /// Build a signing-host runtime config, validating fields whose
    /// representation cannot be made invalid by Rust types alone.
    pub fn new(
        host_info: HostInfo,
        platform_info: PlatformInfo,
        people_chain_genesis_hash: [u8; 32],
        bulletin_chain_genesis_hash: [u8; 32],
    ) -> Result<Self, RuntimeConfigValidationError> {
        Ok(Self {
            host: HostRuntimeConfig::new(host_info, platform_info)?,
            people_chain_genesis_hash,
            bulletin_chain_genesis_hash,
        })
    }
}

impl ProductContext {
    /// Build a product context, validating fields whose representation cannot
    /// be made invalid by Rust types alone.
    pub fn new(product_id: String) -> Result<Self, RuntimeConfigValidationError> {
        Self::new_with_execution(product_id, ProductExecutionKind::Spa)
    }

    /// Build a product context for a host-selected executable kind.
    pub fn new_with_execution(
        product_id: String,
        execution_kind: ProductExecutionKind,
    ) -> Result<Self, RuntimeConfigValidationError> {
        Ok(Self {
            product_id: normalize_product_identifier(&product_id)?,
            execution_kind,
        })
    }
}

/// Decoding routes through [`ProductContext::new_with_execution`] so a frame
/// off the wire cannot produce a context the constructor rejects. The runtime
/// treats a `ProductContext` as already validated (product storage keys are
/// built with `expect`), and derivation/storage scopes are keyed by
/// `product_id`, so an unnormalized id would split one logical product across
/// two scopes.
impl Decode for ProductContext {
    fn decode<I: parity_scale_codec::Input>(
        input: &mut I,
    ) -> Result<Self, parity_scale_codec::Error> {
        let product_id = String::decode(input)?;
        let execution_kind = ProductExecutionKind::decode(input)?;
        Self::new_with_execution(product_id, execution_kind)
            .map_err(|_| "ProductContext.product_id is not an accepted product identifier".into())
    }
}

/// Whether `identifier` is a product scope the core is allowed to derive for.
pub fn is_product_identifier(identifier: &str) -> bool {
    normalize_product_identifier(identifier).is_ok()
}

/// Top-level domains that dotNS deployments register product names under.
pub const DOTNS_TLDS: &[&str] = &["dot", "paseo"];

/// Whether `normalized` ends in one of [`DOTNS_TLDS`]. Expects an
/// already-lowercased host with no trailing root dot.
pub fn has_dotns_tld(normalized: &str) -> bool {
    normalized
        .rsplit_once('.')
        .is_some_and(|(_, tld)| DOTNS_TLDS.contains(&tld))
}

/// Normalize product identifiers before derivation and policy checks.
pub fn normalize_product_identifier(
    product_id: &str,
) -> Result<String, RuntimeConfigValidationError> {
    let trimmed = product_id.trim();
    require_non_empty("product_id", trimmed)?;
    let normalized = trimmed.nfc().collect::<String>().to_lowercase();
    if has_dotns_tld(&normalized)
        || normalized == "localhost"
        || normalized.starts_with("localhost:")
    {
        Ok(normalized)
    } else {
        Err(RuntimeConfigValidationError::InvalidProductId {
            product_id: product_id.to_string(),
        })
    }
}

/// Largest accepted length for a product-supplied chat identifier or display
/// name, in bytes.
pub const CHAT_FIELD_MAX_BYTES: usize = 256;

/// Largest accepted length for a product-supplied chat icon, in bytes. Wide
/// enough for a `data:` thumbnail, far below the transport frame cap.
pub const CHAT_ICON_MAX_BYTES: usize = 64 * 1024;

/// Inline image media types a chat icon may carry. SVG is excluded: it can
/// carry script.
const ALLOWED_ICON_DATA_TYPES: [&str; 5] = [
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp",
    "image/avif",
];

/// Normalize a product-supplied chat room or bot identifier.
///
/// Screened harder than a display name, mirroring
/// [`normalize_product_identifier`]: an identifier is matched, not read, so it
/// also rejects the invisible characters a name legitimately needs — joiners,
/// variation selectors, soft hyphens and non-ASCII spaces — which would
/// otherwise let two distinct ids render identically.
pub fn normalize_chat_identifier(field: &'static str, id: &str) -> Result<String, ChatFieldError> {
    let normalized = normalize_chat_text(field, id)?;
    if normalized.is_empty() {
        return Err(ChatFieldError::Empty { field });
    }
    if normalized.chars().any(is_identifier_unsafe) {
        return Err(ChatFieldError::UnsafeCharacter { field });
    }
    Ok(normalized)
}

/// Validate a product-supplied chat display name.
pub fn validate_chat_name(field: &'static str, name: &str) -> Result<String, ChatFieldError> {
    normalize_chat_text(field, name)
}

/// Trim, NFC-normalize and screen one product-supplied chat string.
///
/// The byte budget applies to the normalized value, which is what a host
/// receives: NFC can expand the input.
fn normalize_chat_text(field: &'static str, value: &str) -> Result<String, ChatFieldError> {
    let normalized = value.trim().nfc().collect::<String>();
    if normalized.len() > CHAT_FIELD_MAX_BYTES {
        return Err(ChatFieldError::TooLong {
            field,
            limit: CHAT_FIELD_MAX_BYTES,
        });
    }
    if normalized.chars().any(is_display_unsafe) {
        return Err(ChatFieldError::UnsafeCharacter { field });
    }
    Ok(normalized)
}

/// Validate a product-supplied chat icon: absent, an `https` URL, or an inline
/// image in [`ALLOWED_ICON_DATA_TYPES`].
///
/// An allowlist rather than a denylist, because a URL parser reaches a scheme
/// through whitespace, tabs and NUL that a prefix comparison does not.
pub fn validate_chat_icon(field: &'static str, icon: &str) -> Result<String, ChatFieldError> {
    let trimmed = icon.trim();
    if trimmed.is_empty() {
        return Ok(String::new());
    }
    if trimmed.len() > CHAT_ICON_MAX_BYTES {
        return Err(ChatFieldError::TooLong {
            field,
            limit: CHAT_ICON_MAX_BYTES,
        });
    }

    match icon_scheme(trimmed).as_deref() {
        Some("https") => Url::parse(trimmed)
            .ok()
            .filter(|parsed| parsed.scheme() == "https")
            .map(|_| trimmed.to_string())
            .ok_or(ChatFieldError::RejectedScheme { field }),
        Some("data") if is_allowed_icon_data_url(trimmed) => Ok(trimmed.to_string()),
        _ => Err(ChatFieldError::RejectedScheme { field }),
    }
}

/// Scheme a URL parser would resolve, with the characters parsers ignore
/// removed so `java\tscript:` and a leading NUL cannot hide one.
fn icon_scheme(candidate: &str) -> Option<String> {
    let stripped: String = candidate
        .chars()
        .filter(|character| !character.is_whitespace() && *character != '\u{0}')
        .collect();
    let (scheme, _) = stripped.split_once(':')?;
    if scheme.is_empty()
        || !scheme
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '-' || c == '.')
    {
        return None;
    }
    Some(scheme.to_ascii_lowercase())
}

/// Whether an inline image declares an allowed media type. The media type is
/// read the way a data-URL processor reads it: whitespace-insensitive.
fn is_allowed_icon_data_url(candidate: &str) -> bool {
    let Some(rest) = candidate
        .char_indices()
        .find(|(_, c)| *c == ':')
        .map(|(index, _)| &candidate[index + 1..])
    else {
        return false;
    };
    let media_type: String = rest
        .split(&[',', ';'][..])
        .next()
        .unwrap_or_default()
        .chars()
        .filter(|character| !character.is_whitespace())
        .collect::<String>()
        .to_ascii_lowercase();
    ALLOWED_ICON_DATA_TYPES.contains(&media_type.as_str())
}

/// Invisible characters an identifier must not carry. A display name keeps
/// these: ZWJ builds emoji sequences and ZWNJ is required by Persian.
fn is_identifier_unsafe(character: char) -> bool {
    matches!(
        character,
        '\u{00ad}'                        // soft hyphen
            | '\u{200c}' | '\u{200d}'     // ZWNJ, ZWJ
            | '\u{2060}'..='\u{2064}'     // word joiner, invisible operators
            | '\u{fe00}'..='\u{fe0f}'     // variation selectors
    ) || (character.is_whitespace() && character != ' ')
}

/// Control characters and bidi overrides let two distinct values render alike.
fn is_display_unsafe(character: char) -> bool {
    character.is_control()
        || matches!(
            character,
            '\u{200b}'
                | '\u{061c}'
                | '\u{202a}'..='\u{202e}'
                | '\u{2066}'..='\u{2069}'
                | '\u{feff}'
                | '\u{e0000}'..='\u{e007f}'
        )
}

/// Rejection of a product-supplied chat field.
#[derive(Debug, Clone, PartialEq, Eq, derive_more::Display, derive_more::Error)]
pub enum ChatFieldError {
    /// The field is required and arrived blank.
    #[display("{field} must not be empty")]
    Empty {
        /// Offending field name.
        field: &'static str,
    },
    /// The field exceeded its byte budget.
    #[display("{field} must be at most {limit} bytes")]
    TooLong {
        /// Offending field name.
        field: &'static str,
        /// Accepted maximum.
        limit: usize,
    },
    /// The field carried characters that make values indistinguishable.
    #[display("{field} must not contain control or bidirectional characters")]
    UnsafeCharacter {
        /// Offending field name.
        field: &'static str,
    },
    /// The icon carried a scheme a host must not render.
    #[display("{field} carries a scheme that cannot be rendered")]
    RejectedScheme {
        /// Offending field name.
        field: &'static str,
    },
}

fn require_non_empty(field: &'static str, value: &str) -> Result<(), RuntimeConfigValidationError> {
    if value.trim().is_empty() {
        return Err(RuntimeConfigValidationError::EmptyField { field });
    }
    Ok(())
}

/// Runtime config validation error.
#[derive(Debug, Clone, PartialEq, Eq, derive_more::Display, derive_more::Error)]
pub enum RuntimeConfigValidationError {
    /// Required string field was empty or whitespace-only.
    #[display("{field} must not be empty")]
    EmptyField {
        /// Field name.
        field: &'static str,
    },
    /// Host icon URL could not be parsed as an absolute HTTPS URL.
    #[display("host_info.icon must be an absolute HTTPS URL: {source}")]
    InvalidHostIcon {
        /// Parse failure.
        source: url::ParseError,
    },
    /// Host icon URL used a non-HTTPS scheme.
    #[display("host_info.icon must use https scheme, got {scheme:?}")]
    InsecureHostIcon {
        /// Actual URL scheme.
        scheme: String,
    },
    /// Pairing deeplink scheme included a URL separator.
    #[display("pairing_deeplink_scheme must not include ://, got {scheme:?}")]
    InvalidDeeplinkScheme {
        /// Actual deeplink scheme value.
        scheme: String,
    },
    /// Product id was not a dotNS or localhost product identifier.
    #[display("product_id must be a dotNS or localhost product identifier, got {product_id:?}")]
    InvalidProductId {
        /// Actual product id value.
        product_id: String,
    },
}

const PRODUCT_STORAGE_KEY_PREFIX: &str = "truapi:product-storage:v1:";

/// Decoded product scope and product-owned key used by [`ProductStorage`].
///
/// The string representation remains the host callback ABI. Native hosts that
/// need separate backing stores can decode it without duplicating the wire
/// format.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProductStorageKey {
    product_id: String,
    key: String,
}

impl ProductStorageKey {
    /// Build a key with a validated, normalized product id.
    pub fn new(
        product_id: &str,
        key: impl Into<String>,
    ) -> Result<Self, RuntimeConfigValidationError> {
        Ok(Self {
            product_id: normalize_product_identifier(product_id)?,
            key: key.into(),
        })
    }

    /// Decode the opaque key passed through [`ProductStorage`].
    pub fn decode(value: &str) -> Result<Self, String> {
        let remainder = value
            .strip_prefix(PRODUCT_STORAGE_KEY_PREFIX)
            .ok_or_else(|| "product storage key has an unknown format".to_string())?;
        let (length, scoped) = remainder
            .split_once(':')
            .ok_or_else(|| "product storage key is missing its scope length".to_string())?;
        let product_length = length
            .parse::<usize>()
            .map_err(|_| "product storage key has an invalid scope length".to_string())?;
        let product_id = scoped
            .get(..product_length)
            .ok_or_else(|| "product storage key has a truncated product id".to_string())?;
        let separator = scoped
            .as_bytes()
            .get(product_length)
            .copied()
            .ok_or_else(|| "product storage key is missing its key separator".to_string())?;
        if separator != b':' {
            return Err("product storage key has an invalid key separator".to_string());
        }
        let key = scoped
            .get(product_length + 1..)
            .ok_or_else(|| "product storage key splits a UTF-8 character".to_string())?;
        Self::new(product_id, key.to_string()).map_err(|error| error.to_string())
    }

    /// Product identifier owning this storage key.
    pub fn product_id(&self) -> &str {
        &self.product_id
    }

    /// Product-local key without the host scope prefix.
    pub fn key(&self) -> &str {
        &self.key
    }

    /// Encode the stable opaque key used by existing host callbacks.
    pub fn encode(&self) -> String {
        format!(
            "{PRODUCT_STORAGE_KEY_PREFIX}{}:{}:{}",
            self.product_id.len(),
            self.product_id,
            self.key
        )
    }
}

/// Product-scoped key-value storage.
///
/// The core namespaces product keys before calling this trait. Host
/// implementations may treat `key` as opaque or decode it with
/// [`ProductStorageKey`] when their physical storage is separated by product.
#[async_trait]
pub trait ProductStorage: Send + Sync {
    /// Read a value by key.
    async fn read(&self, key: String) -> Result<Option<Vec<u8>>, HostLocalStorageReadError>;

    /// Write a value to a key.
    async fn write(&self, key: String, value: Vec<u8>) -> Result<(), HostLocalStorageReadError>;

    /// Clear a value at a key.
    async fn clear(&self, key: String) -> Result<(), HostLocalStorageReadError>;
}

/// Open URLs in the system browser. Input is already trimmed, categorized,
/// and (where needed) normalized by the core; the host implementation only
/// needs to hand the URL to the OS URL handler.
#[async_trait]
pub trait Navigation: Send + Sync {
    /// Open the given URL in the system browser.
    async fn navigate_to(&self, url: String) -> Result<(), HostNavigateToError>;
}

/// Deliver push notifications.
#[async_trait]
pub trait Notifications: Send + Sync {
    /// Schedule or immediately display the given notification and return the
    /// host-assigned id.
    async fn push_notification(
        &self,
        notification: HostPushNotificationRequest,
    ) -> Result<HostPushNotificationResponse, GenericError>;

    /// Cancel a notification by id. Idempotent: cancelling an already-fired or
    /// unknown id still returns `Ok(())`.
    async fn cancel_notification(&self, id: NotificationId) -> Result<(), GenericError> {
        let _ = id;
        Ok(())
    }
}

/// Permission prompts. Device permissions (camera, mic, NFC, ...) are separate
/// from remote permissions (domain access, chain submit, ...), so the platform
/// surface mirrors that split.
#[async_trait]
pub trait Permissions: Send + Sync {
    /// Prompt the user for a device-level permission.
    async fn device_permission(
        &self,
        request: HostDevicePermissionRequest,
    ) -> Result<HostDevicePermissionResponse, GenericError>;

    /// Prompt the user for a remote (product-scoped) permission bundle.
    async fn remote_permission(
        &self,
        request: RemotePermissionRequest,
    ) -> Result<RemotePermissionResponse, GenericError>;
}

/// Permission request whose authorization status can be inspected or updated
/// by host administration UI.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum PermissionAuthorizationRequest {
    /// Device-level permission such as camera, microphone, or location.
    Device(HostDevicePermissionRequest),
    /// Remote/product-scoped permission such as chain submit or HTTP access.
    Remote(RemotePermissionRequest),
    /// Product-scoped permission to disclose the user's primary identity.
    IdentityDisclosure,
    /// Product-scoped permission to access another product's account context.
    AccountAccess {
        /// Product whose account context may be accessed.
        target_product_id: String,
    },
}

/// Authorization status for a permission request.
///
/// `NotDetermined` means the core has no persisted answer and will prompt the
/// host the next time the product requests this permission.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum PermissionAuthorizationStatus {
    /// No persisted authorization exists.
    NotDetermined,
    /// Access is denied.
    Denied,
    /// Access is authorized.
    Authorized,
}

/// Core-owned administration API exposed to host UI.
///
/// Hosts call this surface to drive global runtime actions or inspect/update
/// core-owned state without going through a product-scoped TrUAPI request.
#[async_trait]
pub trait CoreAdmin: Send + Sync {
    /// Best-effort logout/disconnect. Clears the active session and emits the
    /// resulting auth state transition.
    async fn disconnect_session(&self) -> Result<(), GenericError>;

    /// Read a stored permission authorization status without prompting.
    async fn get_permission_authorization_status(
        &self,
        request: PermissionAuthorizationRequest,
    ) -> Result<PermissionAuthorizationStatus, GenericError>;

    /// Read stored permission authorization statuses without prompting.
    ///
    /// Results are returned in the same order as `requests`.
    async fn get_permission_authorization_statuses(
        &self,
        requests: Vec<PermissionAuthorizationRequest>,
    ) -> Result<Vec<PermissionAuthorizationStatus>, GenericError>;

    /// Update a stored permission authorization status. `NotDetermined` clears
    /// the stored value so the next product request prompts again.
    async fn set_permission_authorization_status(
        &self,
        request: PermissionAuthorizationRequest,
        status: PermissionAuthorizationStatus,
    ) -> Result<(), GenericError>;
}

/// Pairing-host-only administration API exposed to host UI.
#[async_trait]
pub trait PairingHostAdmin: Send + Sync {
    /// Cancel any in-flight pairing request.
    fn cancel_pairing(&self);

    /// Notify the core that the persisted auth-session blob may have changed.
    ///
    /// The host owns persistence and change detection. The pairing core owns
    /// decoding that blob into live `SessionState` / `AuthState`.
    fn notify_session_store_changed(&self);
}

/// One chain a host serves: a protocol chain role mapped to the concrete
/// chain of the host's configured environment.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct HostChainEntry {
    /// Protocol role this entry answers for.
    pub identifier: ChainIdentifier,
    /// Genesis hash identifying the chain in all chain-scoped calls.
    pub genesis_hash: Bytes32,
}

/// The chain set a host serves: its environment plus one entry per chain role.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct HostChainSet {
    /// Ecosystem the host is configured for, e.g. "polkadot", "paseo".
    pub network: String,
    /// Chains this host serves, keyed by protocol role.
    pub chains: Vec<HostChainEntry>,
}

/// Feature-support probing. The host answers whether it can service a given
/// capability (currently scoped to per-chain support).
#[async_trait]
pub trait Features: Send + Sync {
    /// Report whether the requested feature is supported.
    async fn feature_supported(
        &self,
        request: HostFeatureSupportedRequest,
    ) -> Result<HostFeatureSupportedResponse, GenericError>;

    /// Enumerate the chains this host serves (RFC 0026). The core resolves
    /// `get_chain_info` requests against the returned set.
    async fn supported_chains(&self) -> Result<HostChainSet, GenericError>;
}

/// JSON-RPC provider factory for chain access.
///
/// The platform provides a way to get a JSON-RPC connection for a given chain.
/// The server runtime manages the chainHead v1 state machine on top of this.
/// Host-spec N.6 requires products to access chains through host-mediated
/// providers:
/// <https://github.com/paritytech/host-spec/blob/adb3989208ae1c2107dbf0159611353e6989422c/spec/N-shared-infrastructure.md?plain=1#L91-L102>
#[async_trait]
pub trait ChainProvider: Send + Sync {
    /// Open a JSON-RPC connection for the chain identified by `genesis_hash`.
    /// Drop the returned connection to disconnect.
    async fn connect(
        &self,
        genesis_hash: [u8; 32],
    ) -> Result<Box<dyn JsonRpcConnection>, GenericError>;
}

/// A live JSON-RPC connection to a chain.
pub trait JsonRpcConnection: Send + Sync {
    /// Send a JSON-RPC request string.
    fn send(&self, request: String);

    /// Stream of JSON-RPC response strings.
    fn responses(&self) -> BoxStream<'static, String>;

    /// Close the connection lease.
    ///
    /// Hosts may keep a shared underlying transport alive, but this handle
    /// must stop receiving responses and release any per-caller resources.
    fn close(&self);
}

/// Core-owned host-private storage slots. Products never address these slots;
/// the host chooses the backing store for each slot.
///
/// Storage is host-local; `storage.md` records the current status quo:
/// <https://github.com/paritytech/host-spec/blob/adb3989208ae1c2107dbf0159611353e6989422c/storage.md?plain=1#L1-L7>
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum CoreStorageKey {
    /// Opaque SSO/auth session blob.
    #[codec(index = 0)]
    AuthSession,
    /// Pairing device identity used during SSO flows.
    PairingDeviceIdentity,
    /// Persisted authorization for one product-scoped permission request.
    PermissionAuthorization {
        /// Product whose permission decision is being stored.
        product_id: String,
        /// Permission request whose authorization is being stored.
        request: PermissionAuthorizationRequest,
    },
    /// Persisted allowance-slot keys for one paired SSO session.
    AllowanceKeys {
        /// Stable host-derived SSO session id.
        session_id: String,
    },
    /// Last processed SSO pairing response statement for the pairing device.
    LastProcessedPairingStatement,
    /// Legacy unscoped RFC-0010 AutoSigning secret. Core only addresses this
    /// slot to reject and erase pre-scoping entries.
    AutoSigningKey {
        /// Product whose hard subtree the legacy secret controlled.
        product_id: String,
    },
    /// Wallet-bound RFC-0010 AutoSigning capabilities for the active pairing.
    AutoSigningKeys,
    /// Wallet-bound RFC-0024 ring-VRF registry snapshot.
    #[codec(index = 7)]
    RingVrfRegistry {
        /// Root account public key identifying the wallet that owns the registry.
        root_public_key: [u8; 32],
    },
    /// Statement-store allowance targets the signing host keeps renewed.
    #[codec(index = 8)]
    StatementRenewalTargets,
}

/// Stable metadata describing one strictly decoded [`CoreStorageKey`].
///
/// `kind` is the Rust variant name and is part of the host embedding contract.
/// `product_id` is present only for keys whose storage slot is directly
/// product-indexed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoreStorageKeyDescription {
    /// Stable storage-key variant name.
    pub kind: &'static str,
    /// Product that owns this exact slot, when the key is product-indexed.
    pub product_id: Option<String>,
}

/// Failure to decode exactly one [`CoreStorageKey`].
#[derive(Debug, Clone, PartialEq, Eq, derive_more::Display, derive_more::Error)]
pub enum CoreStorageKeyDescriptionError {
    /// The bytes are not a valid SCALE-encoded key.
    #[display("invalid CoreStorageKey encoding")]
    InvalidEncoding,
    /// A valid key was followed by additional bytes.
    #[display("CoreStorageKey encoding contains trailing bytes")]
    TrailingBytes,
}

/// Strictly decode one SCALE-encoded [`CoreStorageKey`] and return stable
/// metadata suitable for choosing host-private storage policy.
pub fn describe_core_storage_key(
    encoded: &[u8],
) -> Result<CoreStorageKeyDescription, CoreStorageKeyDescriptionError> {
    let mut input = encoded;
    let key = CoreStorageKey::decode(&mut input)
        .map_err(|_| CoreStorageKeyDescriptionError::InvalidEncoding)?;
    if !input.is_empty() {
        return Err(CoreStorageKeyDescriptionError::TrailingBytes);
    }
    let (kind, product_id) = match key {
        CoreStorageKey::AuthSession => ("AuthSession", None),
        CoreStorageKey::PairingDeviceIdentity => ("PairingDeviceIdentity", None),
        CoreStorageKey::PermissionAuthorization { product_id, .. } => {
            ("PermissionAuthorization", Some(product_id))
        }
        CoreStorageKey::AllowanceKeys { .. } => ("AllowanceKeys", None),
        CoreStorageKey::LastProcessedPairingStatement => ("LastProcessedPairingStatement", None),
        CoreStorageKey::AutoSigningKey { product_id } => ("AutoSigningKey", Some(product_id)),
        CoreStorageKey::AutoSigningKeys => ("AutoSigningKeys", None),
        CoreStorageKey::RingVrfRegistry { .. } => ("RingVrfRegistry", None),
        CoreStorageKey::StatementRenewalTargets => ("StatementRenewalTargets", None),
    };
    Ok(CoreStorageKeyDescription { kind, product_id })
}

impl CoreStorageKey {
    /// Persisted authorization key for one product-scoped device permission.
    pub fn device_permission_authorization(
        product_id: &str,
        permission: &HostDevicePermissionRequest,
    ) -> Self {
        Self::PermissionAuthorization {
            product_id: product_id.to_string(),
            request: PermissionAuthorizationRequest::Device(*permission),
        }
    }

    /// Persisted authorization key for one product-scoped remote permission.
    pub fn remote_permission_authorization(
        product_id: &str,
        request: &RemotePermissionRequest,
    ) -> Self {
        Self::PermissionAuthorization {
            product_id: product_id.to_string(),
            request: PermissionAuthorizationRequest::Remote(canonical_remote_request(request)),
        }
    }

    /// Persisted authorization key for product-scoped identity disclosure.
    pub fn identity_disclosure_authorization(product_id: &str) -> Self {
        Self::PermissionAuthorization {
            product_id: product_id.to_string(),
            request: PermissionAuthorizationRequest::IdentityDisclosure,
        }
    }

    /// Persisted authorization key for one product accessing another product's
    /// account context.
    pub fn account_access_authorization(product_id: &str, target_product_id: &str) -> Self {
        Self::PermissionAuthorization {
            product_id: product_id.to_string(),
            request: PermissionAuthorizationRequest::AccountAccess {
                target_product_id: target_product_id.to_string(),
            },
        }
    }
}

fn canonical_remote_request(request: &RemotePermissionRequest) -> RemotePermissionRequest {
    let permission = match &request.permission {
        RemotePermission::Remote { domains } => {
            // DNS domains are case-insensitive, so a logically-identical bundle
            // requested with different casing or duplicate entries must
            // canonicalize to one key (no spurious re-prompt).
            let mut canonical: Vec<String> = domains
                .iter()
                .map(|domain| domain.to_ascii_lowercase())
                .collect();
            canonical.sort();
            canonical.dedup();
            RemotePermission::Remote { domains: canonical }
        }
        other => other.clone(),
    };
    RemotePermissionRequest { permission }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auth_session_storage_key_has_stable_encoding() {
        assert_eq!(CoreStorageKey::AuthSession.encode(), [0]);
    }

    #[test]
    fn product_context_encoding_matches_the_generated_host_codec() {
        // The generated TS host codec is
        // `S.Struct({productId: S.str, executionKind: S.Status("Spa", "Chat")})`,
        // so the field order and the variant indices below are the wire
        // contract every JS host decodes against. The JS half of this pair is
        // `product context encoding matches the Rust platform codec` in
        // `js/packages/truapi-host/src/host-callbacks-adapter.test.ts`, which
        // asserts the same bytes through that generated codec.
        assert_eq!(ProductExecutionKind::Spa.encode(), [0]);
        assert_eq!(ProductExecutionKind::Chat.encode(), [1]);

        let context =
            ProductContext::new_with_execution("app.dot".to_string(), ProductExecutionKind::Chat)
                .expect("product id is valid");
        assert_eq!(
            context.encode(),
            [28, b'a', b'p', b'p', b'.', b'd', b'o', b't', 1]
        );
        assert_eq!(
            ProductContext::decode(&mut context.encode().as_slice()),
            Ok(context)
        );
    }

    #[test]
    fn product_context_decoding_rejects_ids_the_constructor_rejects() {
        // Hand-built frames, not values this crate can encode: `Decode` must
        // apply the same product-id policy as the constructor so decoding
        // cannot mint a context with an unscoped or empty product id.
        for product_id in ["evil.com", "", "  "] {
            let frame = (product_id.to_string(), ProductExecutionKind::Spa).encode();
            assert!(
                ProductContext::decode(&mut frame.as_slice()).is_err(),
                "{product_id:?} must not decode into a ProductContext"
            );
        }
    }

    #[test]
    fn product_context_decoding_normalizes_the_product_id() {
        // Derivation and product-scoped storage are keyed by `product_id`, so
        // a non-canonical id off the wire has to land in the same scope the
        // constructor would produce rather than opening a second one.
        let frame = ("App.DOT".to_string(), ProductExecutionKind::Spa).encode();
        let decoded = ProductContext::decode(&mut frame.as_slice()).expect("product id normalizes");
        assert_eq!(decoded.product_id, "app.dot");
        assert_eq!(
            decoded,
            ProductContext::new("app.dot".to_string()).expect("product id is valid")
        );
    }

    #[test]
    fn core_storage_key_description_is_strict_and_product_scoped() {
        let permission = CoreStorageKey::device_permission_authorization(
            "product.dot",
            &HostDevicePermissionRequest::Camera,
        )
        .encode();
        assert_eq!(
            describe_core_storage_key(&permission),
            Ok(CoreStorageKeyDescription {
                kind: "PermissionAuthorization",
                product_id: Some("product.dot".to_string()),
            })
        );
        for (key, kind, product_id) in [
            (CoreStorageKey::AuthSession, "AuthSession", None),
            (
                CoreStorageKey::PairingDeviceIdentity,
                "PairingDeviceIdentity",
                None,
            ),
            (
                CoreStorageKey::AllowanceKeys {
                    session_id: "session".to_string(),
                },
                "AllowanceKeys",
                None,
            ),
            (
                CoreStorageKey::LastProcessedPairingStatement,
                "LastProcessedPairingStatement",
                None,
            ),
            (
                CoreStorageKey::AutoSigningKey {
                    product_id: "product.dot".to_string(),
                },
                "AutoSigningKey",
                Some("product.dot"),
            ),
            (CoreStorageKey::AutoSigningKeys, "AutoSigningKeys", None),
            (
                CoreStorageKey::RingVrfRegistry {
                    root_public_key: [0x42; 32],
                },
                "RingVrfRegistry",
                None,
            ),
            (
                CoreStorageKey::StatementRenewalTargets,
                "StatementRenewalTargets",
                None,
            ),
        ] {
            let description = describe_core_storage_key(&key.encode()).expect("valid key");
            assert_eq!(description.kind, kind);
            assert_eq!(description.product_id.as_deref(), product_id);
        }

        assert_eq!(
            describe_core_storage_key(&[]),
            Err(CoreStorageKeyDescriptionError::InvalidEncoding)
        );
        let mut trailing = CoreStorageKey::AuthSession.encode();
        trailing.push(0);
        assert_eq!(
            describe_core_storage_key(&trailing),
            Err(CoreStorageKeyDescriptionError::TrailingBytes)
        );
        assert_eq!(
            describe_core_storage_key(&[u8::MAX]),
            Err(CoreStorageKeyDescriptionError::InvalidEncoding)
        );
    }

    #[test]
    fn permission_authorization_keys_separate_product_and_request_variants() {
        let camera = CoreStorageKey::device_permission_authorization(
            "product.dot",
            &HostDevicePermissionRequest::Camera,
        );
        let other_product = CoreStorageKey::device_permission_authorization(
            "other.dot",
            &HostDevicePermissionRequest::Camera,
        );
        let remote = CoreStorageKey::remote_permission_authorization(
            "product.dot",
            &RemotePermissionRequest {
                permission: RemotePermission::ChainSubmit,
            },
        );
        let identity = CoreStorageKey::identity_disclosure_authorization("product.dot");
        let other_product_identity = CoreStorageKey::identity_disclosure_authorization("other.dot");
        let account_access =
            CoreStorageKey::account_access_authorization("product.dot", "target.dot");
        let other_target = CoreStorageKey::account_access_authorization("product.dot", "other.dot");

        assert_ne!(camera, other_product);
        assert_ne!(camera, remote);
        assert_ne!(camera, identity);
        assert_ne!(remote, identity);
        assert_ne!(identity, other_product_identity);
        assert_ne!(account_access, other_target);
        assert_ne!(account_access, camera);
    }

    #[test]
    fn remote_permission_authorization_key_canonicalizes_domain_sets() {
        let unsorted = RemotePermissionRequest {
            permission: RemotePermission::Remote {
                domains: vec!["b.example.com".into(), "a.example.com".into()],
            },
        };
        let sorted = RemotePermissionRequest {
            permission: RemotePermission::Remote {
                domains: vec!["a.example.com".into(), "b.example.com".into()],
            },
        };
        assert_eq!(
            CoreStorageKey::remote_permission_authorization("product.dot", &unsorted),
            CoreStorageKey::remote_permission_authorization("product.dot", &sorted)
        );

        let mixed = RemotePermissionRequest {
            permission: RemotePermission::Remote {
                domains: vec!["Example.COM".into(), "a.com".into(), "a.com".into()],
            },
        };
        let canonical = RemotePermissionRequest {
            permission: RemotePermission::Remote {
                domains: vec!["a.com".into(), "example.com".into()],
            },
        };
        assert_eq!(
            CoreStorageKey::remote_permission_authorization("product.dot", &mixed),
            CoreStorageKey::remote_permission_authorization("product.dot", &canonical)
        );
    }

    #[test]
    fn remote_permission_authorization_key_handles_separator_chars_in_domains() {
        let injecting = RemotePermissionRequest {
            permission: RemotePermission::Remote {
                domains: vec!["a|b".into(), "c,d".into(), "remote:web-rtc".into()],
            },
        };
        let benign_same_set = RemotePermissionRequest {
            permission: RemotePermission::Remote {
                domains: vec!["x".into(), "y".into(), "z".into()],
            },
        };
        let injecting_key =
            CoreStorageKey::remote_permission_authorization("product.dot", &injecting);
        let benign_key =
            CoreStorageKey::remote_permission_authorization("product.dot", &benign_same_set);
        assert_ne!(injecting_key, benign_key);

        let webrtc = RemotePermissionRequest {
            permission: RemotePermission::WebRtc,
        };
        assert_ne!(
            injecting_key,
            CoreStorageKey::remote_permission_authorization("product.dot", &webrtc)
        );

        let injecting_reordered = RemotePermissionRequest {
            permission: RemotePermission::Remote {
                domains: vec!["remote:web-rtc".into(), "c,d".into(), "a|b".into()],
            },
        };
        assert_eq!(
            injecting_key,
            CoreStorageKey::remote_permission_authorization("product.dot", &injecting_reordered)
        );
    }
}

/// Host-private persistence for core-owned state.
#[async_trait]
pub trait CoreStorage: Send + Sync {
    /// Read a core-owned value by typed slot.
    async fn read_core_storage(&self, key: CoreStorageKey)
    -> Result<Option<Vec<u8>>, GenericError>;

    /// Write a core-owned value by typed slot.
    async fn write_core_storage(
        &self,
        key: CoreStorageKey,
        value: Vec<u8>,
    ) -> Result<(), GenericError>;

    /// Clear a core-owned value by typed slot.
    async fn clear_core_storage(&self, key: CoreStorageKey) -> Result<(), GenericError>;
}

/// Decoded session fields a host shell needs to render account UI without
/// parsing the opaque session blob the core persists through [`CoreStorage`].
#[derive(Debug, Clone, Default, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct SessionUiInfo {
    /// 32-byte sr25519 root public key of the active session.
    pub public_key: Bytes32,
    /// Wallet identity account id used for People-chain username lookup.
    pub identity_account_id: Option<Bytes32>,
    /// Short username from the People-chain identity record.
    pub lite_username: Option<String>,
    /// Fully qualified username from the People-chain identity record.
    pub full_username: Option<String>,
}

/// Auth/session lifecycle state the core projects for host UI. The core owns
/// every transition and emits states in order; hosts render the current state
/// and never derive auth UI from any other signal.
#[derive(Debug, Clone, Default, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum AuthState {
    /// No active session and no login in progress.
    #[default]
    Disconnected,
    /// A login is in progress: present the pairing deeplink/QR. Leave this
    /// state only on a subsequent emission (connected, failed, or
    /// disconnected after cancellation).
    Pairing {
        /// Wallet pairing deeplink to render as a QR code or open directly.
        deeplink: String,
    },
    /// A session is active.
    Connected(SessionUiInfo),
    /// The last login attempt failed; show the reason and offer a retry.
    LoginFailed {
        /// What kind of failure this was. Hosts branch on this and treat
        /// `reason` as display copy only.
        kind: LoginFailureKind,
        /// Human-readable failure reason.
        reason: String,
    },
    /// The wallet accepted the pairing request and the core is resolving and
    /// persisting the session. Hosts should replace the pairing QR with an
    /// in-progress presentation until a terminal state is emitted.
    Authenticating,
}

/// Why a login attempt failed, for hosts that need to act on the cause rather
/// than only display it.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum LoginFailureKind {
    /// The wallet has no free statement-store allowance slot for this period,
    /// so it cannot register the device — which normally holds until the period
    /// rolls over, making a retry a waste of the user's remaining budget.
    ///
    /// Recovered heuristically from the wallet's prose, whose wording is not
    /// this workspace's to pin, so treat it as a strong hint rather than a
    /// proof: do not make retry the primary action, but leave a way to reach it.
    NoFreeAllowanceSlots,
    /// Anything else. `reason` carries the detail.
    #[default]
    Other,
}

/// Host auth UI driven by core-owned [`AuthState`] transitions.
pub trait AuthPresenter: Send + Sync {
    /// Observe an auth state change, in transition order. A pairing host's
    /// session activation reports its outcome even when it is the default
    /// `Disconnected`, so a host that awaits activation before routing never
    /// has to read silence as "signed out". Every other emission, and every
    /// emission on a host role that has no session activation, happens only
    /// when the state actually changes. Default is a no-op for hosts that
    /// render no auth UI.
    fn auth_state_changed(&self, state: AuthState) {
        let _ = state;
    }
}

/// Review shown before a sign-payload request is sent to the paired wallet.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum SignPayloadReview {
    /// Product-account signing request.
    Product(HostSignPayloadRequest),
    /// Legacy-account signing request.
    LegacyAccount(HostSignPayloadWithLegacyAccountRequest),
}

/// Review shown before a sign-raw request is sent to the paired wallet.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum SignRawReview {
    /// Product-account raw signing request.
    Product(HostSignRawRequest),
    /// Legacy-account raw signing request.
    LegacyAccount(HostSignRawWithLegacyAccountRequest),
}

/// Review shown before a product account signs a Statement Store proof
/// payload. Distinct from raw-message signing: the payload is the exact
/// unsigned statement, signed as-is (no `<Bytes>` envelope), so the host must
/// not present it with the raw-signing convention.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct StatementStoreProductSignReview {
    /// Product account that will sign the statement payload.
    pub account: ProductAccountId,
    /// Exact unsigned statement payload to be signed.
    pub payload: Vec<u8>,
}

/// Review shown before a transaction-creation request is sent to the paired wallet.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum CreateTransactionReview {
    /// Product-account transaction request.
    Product(ProductAccountTxPayload),
    /// Legacy-account transaction request.
    LegacyAccount(LegacyAccountTxPayload),
}

/// Review shown before a product derives a contextual alias (RFC 0004).
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct AccountAliasReview {
    /// Product requesting the alias.
    pub calling_product_id: String,
    /// Product-scoped context the alias is bound to.
    pub context: ProductProofContext,
    /// Ring the alias is derived against.
    pub ring_location: RingLocation,
}

/// Review shown before a product creates a ring-VRF proof (RFC 0004).
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct CreateProofReview {
    /// Product requesting the proof.
    pub calling_product_id: String,
    /// Product-scoped context the proof's alias is bound to.
    pub context: ProductProofContext,
    /// Ring the proof is generated against.
    pub ring_location: RingLocation,
    /// Opaque message bound into the proof.
    pub message: Vec<u8>,
}

/// Review shown before signing an RFC-0023 VRF transcript.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct SignVrfReview {
    /// Product making the request.
    pub calling_product_id: String,
    /// Product account and exact ordered transcript.
    pub request: HostAccountSignVrfRequest,
}

/// Review shown before allocating resources for a product. Names the
/// beneficiary product so the user knows which product receives the
/// (signing-capable) allowance key they are approving.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct ResourceAllocationReview {
    /// Product the allocation is requested for.
    pub calling_product_id: String,
    /// Resources to allocate.
    pub resources: Vec<AllocatableResource>,
}

/// Review shown before a product asks to access another product account.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct AccountAccessReview {
    /// Product currently handling the request.
    pub requesting_product_id: String,
    /// Product whose account is being requested.
    pub target_product_id: String,
}

/// Review shown before a product learns the user's primary identity.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct IdentityDisclosureReview {
    /// Product currently handling the request.
    pub product_id: String,
}

/// Review shown before a preimage is submitted.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct PreimageSubmitReview {
    /// Size of the preimage in bytes.
    pub size: u64,
}

/// Review shown before a user-confirmed core action continues.
#[allow(clippy::large_enum_variant)]
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum UserConfirmationReview {
    /// Sign a SCALE payload with a product or legacy account.
    SignPayload(SignPayloadReview),
    /// Sign raw bytes with a product or legacy account.
    SignRaw(SignRawReview),
    /// Sign a Statement Store proof payload with a product account.
    StatementStoreProductSign(StatementStoreProductSignReview),
    /// Create a transaction with a product or legacy account.
    CreateTransaction(CreateTransactionReview),
    /// Allow a product to derive a contextual alias for a ring.
    AccountAlias(AccountAliasReview),
    /// Allow a product to create a ring-VRF proof for a ring.
    CreateProof(CreateProofReview),
    /// Allow a product to learn the user's primary identity.
    IdentityDisclosure(IdentityDisclosureReview),
    /// Allocate resources for the requesting product.
    ResourceAllocation(ResourceAllocationReview),
    /// Submit a preimage to the host-selected backend.
    PreimageSubmit(PreimageSubmitReview),
    /// Allow a product to access another product account.
    AccountAccess(AccountAccessReview),
    /// Sign an RFC-0023 VRF transcript with a product account.
    SignVrf(SignVrfReview),
}

/// Local user confirmation UI for sensitive core-owned operations.
#[async_trait]
pub trait UserConfirmation: Send + Sync {
    /// Confirm a reviewed action before the core continues.
    async fn confirm_user_action(
        &self,
        review: UserConfirmationReview,
    ) -> Result<bool, GenericError>;
}

/// Host theme source.
pub trait ThemeHost: Send + Sync {
    /// Emits current theme immediately, then future changes. Hosts with no
    /// named themes report `ThemeName::Default`.
    fn subscribe_theme(&self) -> BoxStream<'static, Result<HostThemeSubscribeItem, GenericError>>;
}

/// Host preimage backend. The core builds, signs, and submits the Bulletin
/// `TransactionStorage.store` transaction itself; the host only owns preimage
/// content retrieval (P2P/IPFS lookup).
#[async_trait]
pub trait PreimageHost: Send + Sync {
    /// Emits current value/miss immediately, then future updates.
    fn lookup_preimage(
        &self,
        key: Vec<u8>,
    ) -> BoxStream<'static, Result<Option<Vec<u8>>, GenericError>>;
}

/// Host-implemented adapter through which product Chat calls reach native
/// storage and UI. Installed separately from [`Platform`], and only by the
/// native entrypoints: a WASM/JS host cannot supply one, so requests from a
/// `Chat` execution created there answer unsupported and its subscriptions end
/// empty, which a product cannot tell from a healthy close.
///
/// On `create_room` and `register_bot` the core bounds ids, names and icons,
/// NFC-normalizes them, screens control and bidi characters, and restricts an
/// icon to `https` or an inline raster image. Contextual output escaping,
/// storage limits, and every `post_message` field remain host-owned.
#[async_trait]
pub trait ChatPlatform: Send + Sync {
    /// Create or resolve a product-scoped native chat room.
    async fn create_room(
        &self,
        product: &ProductContext,
        request: HostChatCreateRoomRequest,
    ) -> Result<HostChatCreateRoomResponse, HostChatCreateRoomError>;

    /// Register or resolve a product-scoped native chat bot. Host-owned in the
    /// same way rooms are.
    async fn register_bot(
        &self,
        product: &ProductContext,
        request: HostChatRegisterBotRequest,
    ) -> Result<HostChatRegisterBotResponse, HostChatRegisterBotError>;

    /// Persist a product-authored message in a native chat room. A host that
    /// cannot store a given content variant reports a domain error for it.
    async fn post_message(
        &self,
        product: &ProductContext,
        request: HostChatPostMessageRequest,
    ) -> Result<HostChatPostMessageResponse, HostChatPostMessageError>;

    /// Emit the current product-scoped room list and later replacements.
    fn subscribe_rooms(
        &self,
        product: &ProductContext,
    ) -> BoxStream<'static, HostChatListSubscribeItem>;
}

/// Combined platform interface. A host must provide all capability traits.
pub trait Platform:
    Navigation
    + Notifications
    + Permissions
    + Features
    + ProductStorage
    + CoreStorage
    + ChainProvider
    + AuthPresenter
    + UserConfirmation
    + ThemeHost
    + PreimageHost
{
}

impl<T> Platform for T where
    T: Navigation
        + Notifications
        + Permissions
        + Features
        + ProductStorage
        + CoreStorage
        + ChainProvider
        + AuthPresenter
        + UserConfirmation
        + ThemeHost
        + PreimageHost
{
}
