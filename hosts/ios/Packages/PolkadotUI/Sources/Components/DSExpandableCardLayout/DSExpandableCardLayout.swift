import SwiftUI
import UIKit

public struct DSExpandableCardLayout<Card: View, Details: View>: View {
    private let isExpanded: Bool
    private let onCollapse: (() -> Void)?
    private let card: () -> Card
    private let details: () -> Details

    public init(
        isExpanded: Bool,
        onCollapse: (() -> Void)? = nil,
        @ViewBuilder card: @escaping () -> Card,
        @ViewBuilder details: @escaping () -> Details
    ) {
        self.isExpanded = isExpanded
        self.onCollapse = onCollapse
        self.card = card
        self.details = details
    }

    public var body: some View {
        if #available(iOS 18, *) {
            DSExpandableCardLayoutiOS18(
                isExpanded: isExpanded,
                onCollapse: onCollapse,
                card: card,
                details: details
            )
        } else {
            DSExpandableCardLayoutiOS17(
                isExpanded: isExpanded,
                onCollapse: onCollapse,
                card: card,
                details: details
            )
        }
    }
}
