import Foundation

extension Double {
    func rounded(
        toMultipleOf step: CFTimeInterval,
        rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero
    ) -> CFTimeInterval {
        guard step.isFinite,
              step > 0 else {
            return self
        }
        return (self / step).rounded(rule) * step
    }

    func rounded(
        milliseconds: Double,
        rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero
    ) -> CFTimeInterval {
        rounded(toMultipleOf: milliseconds / 1_000.0, rule: rule)
    }
}
