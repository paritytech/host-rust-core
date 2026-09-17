import SwiftUI
import DesignSystem

/// Maps a health score to the ring's appearance. Scoring lives in `ChainHealth`;
/// this is only how that number is drawn. A fully healthy chain is monochrome (filled + `.fgPrimary`),
/// so any colour on the ring indicates a degradation.
enum ChainStatusRingStyle {
    static func isFilled(for grade: ChainHealthGrade) -> Bool {
        grade == .excellent
    }

    static func arcColor(for grade: ChainHealthGrade) -> Color {
        switch grade {
        case .excellent:
            .fgPrimary
        case .good:
            .fgPrimary
        case .fair:
            .strokeWarning
        case .poor:
            .strokeError
        }
    }
}
