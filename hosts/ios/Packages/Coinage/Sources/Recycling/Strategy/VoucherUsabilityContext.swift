import Foundation

/// Inputs the voucher-usability predicate needs beyond the voucher itself: the current time (for the
/// unload-delay escape hatch) and ring capacities per denomination.
public struct VoucherUsabilityContext: Equatable {
    /// Capacity (max provable ring members) keyed by voucher exponent.
    public let ringCapacities: [Int16: Int]
    public let now: Date

    public init(ringCapacities: [Int16: Int], now: Date) {
        self.ringCapacities = ringCapacities
        self.now = now
    }

    public func capacity(for exponent: Int16) -> Int? {
        ringCapacities[exponent]
    }
}
