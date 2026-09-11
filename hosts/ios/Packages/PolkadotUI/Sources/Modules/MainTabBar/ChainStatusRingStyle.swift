import SwiftUI
import DesignSystem

/// Maps a health score to the ring's appearance. Scoring lives in `ChainHealth`;
/// this is only how that number is drawn. A fully healthy chain is monochrome (filled + `.fgPrimary`),
/// so any colour on the ring indicates a degradation.
enum ChainStatusRingStyle {
    static let fullyHealthyThreshold: Double = 0.75
    static let healthyThreshold: Double = 0.5
    static let warningThreshold: Double = 0.25

    static func isFilled(for health: Double) -> Bool {
        health > fullyHealthyThreshold
    }

    static func arcColor(for health: Double) -> Color {
        if health > fullyHealthyThreshold {
            .fgPrimary
        } else if health > healthyThreshold {
            .bgStatusSuccess
        } else if health > warningThreshold {
            .bgStatusWarning
        } else {
            .bgStatusError
        }
    }
}
