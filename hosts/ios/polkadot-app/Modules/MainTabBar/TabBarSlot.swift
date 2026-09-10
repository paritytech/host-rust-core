import UIKit
import PolkadotUI

/// A non-tab affordance in the bar. Tapping one opens a panel instead of switching tabs.
enum TabBarAction: Hashable {
    case scan
    case spaTabs
}

enum TabBarSlot: Equatable {
    case tab(TabBarItem)
    case action(TabBarAction)
}

extension TabBarSlot {
    var tab: TabBarItem? {
        guard case let .tab(item) = self else {
            return nil
        }
        return item
    }

    func makeBarItem(badge: DSTabBarItem.Badge?, spaTabCount: Int) -> DSTabBarItem {
        switch self {
        case let .tab(item):
            item.makeBarItem(badge: badge)
        case let .action(action):
            action.makeBarItem(spaTabCount: spaTabCount)
        }
    }
}

extension TabBarAction {
    func makeBarItem(spaTabCount: Int) -> DSTabBarItem {
        DSTabBarItem(
            content: content(spaTabCount: spaTabCount),
            title: nil,
            role: .action,
            accessibilityLabel: accessibilityLabel(spaTabCount: spaTabCount)
        )
    }
}

private extension TabBarAction {
    func content(spaTabCount: Int) -> DSTabBarItem.Content {
        switch self {
        case .scan:
            .icon(UIImage.tabScan.withRenderingMode(.alwaysTemplate))
        case .spaTabs:
            .tabsGlyph(count: spaTabCount)
        }
    }

    func accessibilityLabel(spaTabCount: Int) -> String {
        switch self {
        case .scan:
            String(localized: .Products.productTabsAccessibilityScanner)
        case .spaTabs:
            String(localized: .Products.productTabsAccessibilityOpenApps(spaTabCount))
        }
    }
}
