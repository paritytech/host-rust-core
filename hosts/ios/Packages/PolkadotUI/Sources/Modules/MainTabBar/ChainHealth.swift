import Foundation

public struct ChainHealthBounds: Hashable {
    public let healthy: Duration
    public let zero: Duration

    public init(healthy: Duration, zero: Duration) {
        self.healthy = healthy
        self.zero = zero
    }
}

public struct ChainHealthCountBounds: Hashable {
    public let healthy: Double
    public let zero: Double

    public init(healthy: Double, zero: Double) {
        self.healthy = healthy
        self.zero = zero
    }
}

public struct ChainHealthThresholds: Hashable {
    public let blockAge: ChainHealthBounds
    public let finalityLag: ChainHealthCountBounds
    public let missingTermGrace: Duration

    public init(
        blockAge: ChainHealthBounds,
        finalityLag: ChainHealthCountBounds,
        missingTermGrace: Duration
    ) {
        self.blockAge = blockAge
        self.finalityLag = finalityLag
        self.missingTermGrace = missingTermGrace
    }
}

/// Named bands of the health score. Owns the thresholds; `ChainStatusRingStyle` draws them.
public enum ChainHealthGrade: Hashable {
    case excellent
    case good
    case fair
    case poor

    public init(health: Double) {
        self =
            if health > 0.75 {
                .excellent
            } else if health > 0.5 {
                .good
            } else if health > 0.25 {
                .fair
            } else {
                .poor
            }
    }
}

public enum ChainHealth {
    public static func score(for viewModel: ChainConnectionStatusViewModel, at date: Date) -> Double {
        guard viewModel.state == .connected else {
            return 0
        }

        let thresholds = viewModel.thresholds

        let blockAgeTerm = elapsedScore(since: viewModel.lastBlockDate, at: date, bounds: thresholds.blockAge)
        let finalityLagTerm = viewModel.finalityLag.map { linearScore(Double($0), bounds: thresholds.finalityLag) }

        // Grace period: while within missingTermGrace of connection, omit nil terms.
        // After grace expires, nil terms become 0.
        // Nil connectedSince while connected is treated as grace-expired.
        let inGrace: Bool =
            if let connectedSinceDate = viewModel.connectedSince {
                date.timeIntervalSince(connectedSinceDate) < thresholds.missingTermGrace.timeInterval
            } else {
                false
            }

        let terms: [Double?] = [blockAgeTerm, finalityLagTerm]
        let scoredTerms = inGrace
            ? terms.compactMap { $0 }
            : terms.map { $0 ?? 0 }

        return scoredTerms.min() ?? 0
    }
}

private extension ChainHealth {
    static func elapsedScore(since date: Date?, at now: Date, bounds: ChainHealthBounds) -> Double? {
        guard let date else {
            return nil
        }

        return linearScore(now.timeIntervalSince(date), within: bounds)
    }

    // Linear scoring: full health at or below `healthy`, 0 at or above `zero`, linear between.
    static func linearScore(_ value: Double, healthy: Double, zero: Double) -> Double {
        if value <= healthy {
            1
        } else if value >= zero {
            0
        } else {
            1 - (value - healthy) / (zero - healthy)
        }
    }

    static func linearScore(_ elapsed: TimeInterval, within bounds: ChainHealthBounds) -> Double {
        linearScore(elapsed, healthy: bounds.healthy.timeInterval, zero: bounds.zero.timeInterval)
    }

    static func linearScore(_ value: Double, bounds: ChainHealthCountBounds) -> Double {
        linearScore(value, healthy: bounds.healthy, zero: bounds.zero)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
