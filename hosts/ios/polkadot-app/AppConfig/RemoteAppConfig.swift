import Foundation

// Built from individual Firebase RemoteConfig keys:
//   identity_backend_url, ipfs_gateway_url, game_dashboard_url, dot_ns_config, coinage_instance_id,
//   funding_domain, funding_config { onrampUrl, offrampUrl }
// Each field nil if the corresponding key is missing or empty.
struct RemoteAppConfig {
    let identityBackendUrl: URL?
    let ipfsGatewayUrl: URL?
    let gameDashboardUrl: URL?
    let dotNsResolver: String?
    /// Absent in payloads published before manifest support, which disables manifest
    /// resolution and leaves legacy resolution working.
    let dotNsNameRegistry: String?
    let coinageInstanceId: UInt32?
    /// Legacy label of the funding product. Superseded by `fundingUrl`; kept one release as the
    /// allowlist-label fallback.
    let fundingDomain: String?
    /// Product destinations the CASH card opens for top up and withdraw, from the `funding_config`
    /// remote object, as published: a dot-domain (`getcash.dot`) or a full URL with a path
    /// (`https://getcash.dot/offramp`). Not part of `isValid`: a payload without them keeps the rest of the
    /// config usable and only the
    /// CASH card entry points report unavailable.
    let fundingUrl: String?
    let offrampUrl: String?
}

extension RemoteAppConfig {
    var isValid: Bool {
        var result = identityBackendUrl != nil
            && ipfsGatewayUrl != nil
            && dotNsResolver != nil
            && coinageInstanceId != nil

        #if TESTNET_FEATURE
            result = result && gameDashboardUrl != nil
        #endif

        return result
    }
}
