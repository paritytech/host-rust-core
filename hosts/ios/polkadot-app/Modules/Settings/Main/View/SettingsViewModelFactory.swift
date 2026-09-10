import ExternalAccessibility
import Foundation
import SwiftUI
import PolkadotUI
import Coinage

struct SettingsContentInput {
    let visibleCells: Set<SettingsViewModel.CellType>
    let attentionItems: Set<SettingsViewModel.CellType>
    let selectedCurrencyCode: String?
    let selectedThemeName: String?
    let selectedPrivacyStrategy: RecyclingStrategyType?
    let appVersion: String?
    let onSelect: (SettingsViewModel.CellType) -> Void
    let onSelectPrivacyStrategy: (RecyclingStrategyType) -> Void
}

protocol SettingsViewModelMaking {
    func makeContent(_ input: SettingsContentInput) -> SettingsViewModel.Content
}

final class SettingsViewModelFactory: SettingsViewModelMaking {
    func makeContent(_ input: SettingsContentInput) -> SettingsViewModel.Content {
        let sections: [SettingsViewLayout.Section] = SettingsViewModel.Section.allCases
            .compactMap { section -> SettingsViewLayout.Section? in
                let cells = section.cells.filter(input.visibleCells.contains)
                guard !cells.isEmpty else { return nil }
                return SettingsViewLayout.Section(
                    id: section.rawValue,
                    header: section.header,
                    leadingContent: privacyLeadingContent(for: section, input: input),
                    items: cells.map { cellType in
                        makeItem(
                            cellType: cellType,
                            attentionItems: input.attentionItems,
                            selectedCurrencyCode: input.selectedCurrencyCode,
                            selectedThemeName: input.selectedThemeName,
                            onSelect: input.onSelect
                        )
                    }
                )
            }
        return SettingsViewModel.Content(sections: sections, appVersion: input.appVersion)
    }
}

private extension SettingsViewModelFactory {
    func privacyLeadingContent(
        for section: SettingsViewModel.Section,
        input: SettingsContentInput
    ) -> AnyView? {
        guard section == .security, let selectedStrategy = input.selectedPrivacyStrategy else { return nil }
        return AnyView(
            PaymentPrivacyModeCard(selected: selectedStrategy, onSelect: input.onSelectPrivacyStrategy)
        )
    }

    func makeItem(
        cellType: SettingsViewModel.CellType,
        attentionItems: Set<SettingsViewModel.CellType>,
        selectedCurrencyCode: String?,
        selectedThemeName: String?,
        onSelect: @escaping (SettingsViewModel.CellType) -> Void
    ) -> DSMenuListItem {
        let needsAttention = attentionItems.contains(cellType)
        return DSMenuListItem(
            id: cellType,
            title: cellType.title,
            description: needsAttention ? cellType.attentionDetails?.message : nil,
            style: needsAttention ? .attention : .default,
            icon: icon(for: cellType),
            rightSlot: rightSlot(
                for: cellType,
                selectedCurrencyCode: selectedCurrencyCode,
                selectedThemeName: selectedThemeName
            ),
            accessibilityId: AccessibilityID.Settings.menuItem(for: cellType),
            action: { onSelect(cellType) }
        )
    }

    func icon(for cellType: SettingsViewModel.CellType) -> ImageResource? {
        switch cellType {
        case .backup: .iconCloud
        case .theme: .iconPalette
        case .currency: .iconDollar
        case .linkedDevices: .iconLaptopMinimal
        case .apps: .iconGrid
        case .blockedUsers: .iconBlock
        case .termsOfUse,
             .privacy: .iconFile
        case .contactUs: .iconCircleHelp
        }
    }

    func rightSlot(
        for cellType: SettingsViewModel.CellType,
        selectedCurrencyCode: String?,
        selectedThemeName: String?
    ) -> DSMenuListItemRightSlot.Style? {
        switch cellType {
        case .theme:
            selectedThemeName.map(DSMenuListItemRightSlot.Style.labelChevron)
        case .currency:
            if let selectedCurrencyCode {
                .labelChevron(selectedCurrencyCode)
            } else {
                .chevron
            }
        case .backup,
             .linkedDevices,
             .apps,
             .blockedUsers,
             .termsOfUse,
             .privacy,
             .contactUs:
            .chevron
        }
    }
}
