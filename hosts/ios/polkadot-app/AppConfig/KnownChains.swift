import Foundation
import SubstrateSdk

/// dotNS TLD of the network the chains below belong to, passed to the core as
/// `HostRuntimeConfig.networkSuffix`. The wallet's reserved identities are
/// derived under it, so it has to name the same network the chains do: a wrong
/// value derives a different person from the same seed rather than failing.
///
/// It lives beside the chain selection, under the same conditions, so the two
/// cannot drift apart.
enum KnownNetworkSuffix {
    #if UNSTABLE
        static let current = "testnet"
    #elseif NIGHTLY
        static let current = "paseo"
    #else
        // Unconfirmed, tracked by
        // https://github.com/paritytech/host-rust-core/issues/760. The Release
        // chains carry the same assets as the nightly ones, `pas` in the native
        // slot and `pusd` alongside it, which points at Paseo rather than
        // Polkadot. No CI configuration builds this branch.
        static let current = "paseo"
    #endif
}

enum KnownChainId {
    #if UNSTABLE
        static let previewNetPeople = "preview-people"
        static let previewNetBulletIn = "preview-bulletin"
        static let polkadotAH = "68d56f15f85d3136970ec16946040bc1752654e906147f7e43e9d539d7c3de2f"
        static let polkadotPeople = "67fa177a097bfa18f77ea95ab56e9bcdfeb0e5b8a40e46298bb93e16b6fc5008"
        static let hydration = "afdc188f45c71dacbaa0b62e16a91f726c7b8699a9748cdf715459de6b7f366d"
        static let paseoBulletIn = "paseo-bulletin"
        static let paseoAH = "paseo-asset-hub"
        static let previewAH = "preview-ah"
    #elseif NIGHTLY
        static let paseoRelay = "nightly-relay"
        static let paseoAH = "nightly-ah"
        static let paseoPeople = "nightly-people"
        static let paseoBulletIn = "nightly-bulletin"
    #else
        static let releaseRelay = "release-relay"
        static let releaseAH = "release-ah"
        static let releasePeople = "release-people"
        static let releaseBulletIn = "release-bulletin"
    #endif
}
