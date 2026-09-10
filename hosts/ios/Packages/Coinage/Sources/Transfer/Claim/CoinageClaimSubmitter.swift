import Foundation
import ExtrinsicService
import SDKLogger

/// A coin a peer handed us, ready to claim: its keypair and the on-chain value exponent to mint into.
struct ClaimableCoin {
    let privateKey: Data
    let publicKey: Data
    let valueExponent: Int16
}

/// Claims coins a peer handed us: each is transferred into a fresh address of ours, registered through
/// the durability layer under one `groupId` so the whole claim group is recorded or none of it is.
///
/// The peer's key is a `Received` input — never a local asset — so the ledger holds it against exactly
/// one non-failure claim without us ever minting it. A retry after a `FAILURE` is safe: the failed
/// entry released its claim, so a fresh attempt mints a new destination and registers again.
protocol CoinageClaimSubmitting: Sendable {
    /// Registers one claim per coin and returns once registration commits — not settlement. Status is
    /// observed via ``CoinageTxServicing/subscribeOperationGroupStatuses(_:)`` for `groupId`.
    func submit(claimable: [ClaimableCoin], groupId: CoinageTxGroupId) async throws
}

final class CoinageClaimSubmitter: CoinageClaimSubmitting, @unchecked Sendable {
    private let minter: any CoinMinting
    private let originFactory: any OriginCreating
    private let txService: any CoinageTxServicing
    private let logger: SDKLoggerProtocol?

    init(
        minter: any CoinMinting,
        originFactory: any OriginCreating,
        txService: any CoinageTxServicing,
        logger: SDKLoggerProtocol?
    ) {
        self.minter = minter
        self.originFactory = originFactory
        self.txService = txService
        self.logger = logger
    }

    func submit(claimable: [ClaimableCoin], groupId: CoinageTxGroupId) async throws {
        guard !claimable.isEmpty else { return }

        // Each claim is signed by a different peer key, so these are distinct origins built
        // independently and registered together — atomically under one groupId.
        var requests: [CoinageTxRequest] = []
        for coin in claimable {
            try await requests.append(buildClaim(coin, groupId: groupId))
        }

        logger?.debug("Registering \(requests.count) claim(s) for group \(groupId)")
        try await txService.submitTransactions(requests, groupId: groupId)
    }
}

// MARK: - Private

private extension CoinageClaimSubmitter {
    /// Mints a fresh destination coin (persisted on allocation, so registration can link the output
    /// row) and builds a transfer of the received coin into it, signed by the peer's key.
    func buildClaim(_ coin: ClaimableCoin, groupId: CoinageTxGroupId) async throws -> CoinageTxRequest {
        let destination = try await minter.mintCoin(exponent: coin.valueExponent)

        let wallet = try CoinDerivedWallet(privateKey: coin.privateKey, publicKey: coin.publicKey)
        let origin = try originFactory.createAsCoinOrigin(for: wallet)

        let call = CoinagePallet.Calls.Transfer(to: destination.publicKey)
        let builder: ExtrinsicBuilderClosure = { try $0.adding(call: call.callAsFunction()) }

        logger?.debug("Built claim group=\(groupId) value=\(coin.valueExponent)")

        return CoinageTxRequest(
            inputs: [.coin(.received(coin.publicKey))],
            outputs: [.coin(destination.derivationIndex, destination.publicKey)],
            builder: builder,
            origin: origin
        )
    }
}
