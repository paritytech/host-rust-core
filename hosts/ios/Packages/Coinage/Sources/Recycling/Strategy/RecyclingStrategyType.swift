import Foundation
import SubstrateSdk

/// The user-chosen privacy preset. The raw value is the persisted key.
public enum RecyclingStrategyType: String, CaseIterable, Equatable, Sendable {
    case minPrivacy
    case balanced
    case maxPrivacy
}

public extension RecyclingStrategyType {
    /// Unload mints a coin's successor at age 1, so nothing below this can exist on chain.
    static let minRecyclableAge: Int16 = 1

    private static let balancedAgeDivisor: Int16 = 3

    /// Resolves the preset into concrete parameters. `forcedRecyclingAge` is the chain ceiling
    /// (`getCoinRecyclingAge()` = `coinMaxAge - 2`), the anchor the presets are expressed against.
    func params(forcedRecyclingAge: Int16) -> RecyclingParams {
        switch self {
        case .minPrivacy:
            // Zero budget never voluntarily gates; only the chain-limits decorator forces coins at
            // the ceiling. Reproduces today's behaviour, which is why it is the default.
            RecyclingParams(
                maxUnavailableBalance: .percent(of: 0),
                minRecyclingAge: forcedRecyclingAge,
                requiredRingFill: .percent(of: 0),
                allowsConfirmedSpend: true
            )
        case .balanced:
            RecyclingParams(
                maxUnavailableBalance: .percent(of: 20),
                minRecyclingAge: max(Self.minRecyclableAge, forcedRecyclingAge / Self.balancedAgeDivisor),
                requiredRingFill: .percent(of: 50),
                allowsConfirmedSpend: true
            )
        case .maxPrivacy:
            // Gates from age 1: unload mints an age-1 successor that is immediately eligible again.
            // Intended — max privacy leans on the quota valve continuously.
            RecyclingParams(
                maxUnavailableBalance: .percent(of: 100),
                minRecyclingAge: Self.minRecyclableAge,
                requiredRingFill: .percent(of: 100),
                allowsConfirmedSpend: false
            )
        }
    }
}
