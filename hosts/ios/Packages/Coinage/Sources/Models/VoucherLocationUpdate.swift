import Operation_iOS

/// The on-chain location a location sync resolves for a voucher — its `remoteState`
/// (onboarding / in-recycler) — keyed by derivation index. Persisted through a dedicated write-only
/// mapper so a location write only ever touches this field, never reading-then-overwriting the rest
/// of the voucher.
public struct VoucherLocationUpdate: Equatable, Sendable {
    public let derivationIndex: DerivationIndex
    public let remoteState: Voucher.OnChainState

    public init(
        derivationIndex: DerivationIndex,
        remoteState: Voucher.OnChainState
    ) {
        self.derivationIndex = derivationIndex
        self.remoteState = remoteState
    }
}

extension VoucherLocationUpdate: Operation_iOS.Identifiable {
    public var identifier: String { Voucher.identifier(for: derivationIndex) }
}
