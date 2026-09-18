import Foundation

/// Identifies one storage key in the location pipeline's batch subscription.
///
/// Member rows are per voucher, but ring state is per *ring*: several vouchers commonly share one,
/// and subscribing per voucher would ask the node for the same key repeatedly. The ring cases are
/// therefore keyed by ``RecyclerKey`` so one request serves every voucher in that ring.
enum SubscriptionKey: Hashable {
    case member(derivationIndex: DerivationIndex)
    case ringStatus(recycler: RecyclerKey)
    case unloadedCount(recycler: RecyclerKey)

    static let separator = ":"

    init?(mappingKey: String) {
        let components = mappingKey.split(separator: Self.separator)

        guard let type = components.first else { return nil }

        switch type {
        case "m":
            guard components.count == 2, let index = DerivationIndex(components[1]) else { return nil }
            self = .member(derivationIndex: index)
        case "rs":
            guard let recycler = Self.recycler(from: components.dropFirst()) else { return nil }
            self = .ringStatus(recycler: recycler)
        case "uc":
            guard let recycler = Self.recycler(from: components.dropFirst()) else { return nil }
            self = .unloadedCount(recycler: recycler)
        default:
            return nil
        }
    }

    var mappingKey: String {
        switch self {
        case let .member(index):
            ["m", "\(index)"].joined(separator: Self.separator)
        case let .ringStatus(recycler):
            (["rs"] + Self.components(of: recycler)).joined(separator: Self.separator)
        case let .unloadedCount(recycler):
            (["uc"] + Self.components(of: recycler)).joined(separator: Self.separator)
        }
    }
}

private extension SubscriptionKey {
    static func components(of recycler: RecyclerKey) -> [String] {
        ["\(recycler.exponent)", "\(recycler.index)"]
    }

    static func recycler(from components: some Collection<Substring>) -> RecyclerKey? {
        let values = Array(components)

        guard values.count == 2,
              let exponent = Int16(values[0]),
              let index = UInt32(values[1])
        else { return nil }

        return RecyclerKey(exponent: exponent, index: index)
    }
}
