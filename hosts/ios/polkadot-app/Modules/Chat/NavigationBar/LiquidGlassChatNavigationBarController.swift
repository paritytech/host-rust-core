import ExternalAccessibility
import PolkadotUI
import UIKit
import SnapKit

@available(iOS 26.0, *)
@MainActor
final class LiquidGlassChatNavigationBarController: ChatNavigationBarControlling {
    private weak var navigationItem: UINavigationItem?
    private let titleView: ChatHeaderView
    private let onStartCall: (ChatCallType) -> Void

    private var headerConfiguration: ChatHeaderConfiguration?
    private var pinnedTitle: String?
    private var pinnedTitlePill: PolkadotPrizesNavTitlePill?
    private var callActions: [ChatCallType] = []
    private var contactMenu: UIMenu?

    init(
        navigationItem: UINavigationItem,
        titleView: ChatHeaderView,
        onStartCall: @escaping (ChatCallType) -> Void
    ) {
        self.navigationItem = navigationItem
        self.titleView = titleView
        self.onStartCall = onStartCall
    }

    func configure() {
        applyClearBackground()
        navigationItem?.style = .editor
        navigationItem?.leftItemsSupplementBackButton = true

        let avatarItem = UIBarButtonItem(customView: titleView)
        avatarItem.hidesSharedBackground = true

        navigationItem?.leftBarButtonItem = avatarItem
        applyHeader()
    }

    func apply(callActions: [ChatCallType]) {
        self.callActions = callActions
        refreshRightBarButtonItems()
    }

    func apply(contactMenu: UIMenu?) {
        self.contactMenu = contactMenu
        refreshContactMenuPresentation()
    }

    func update(headerConfiguration: ChatHeaderConfiguration) {
        self.headerConfiguration = headerConfiguration
        applyHeader()
    }

    func setPinnedTitle(_ title: String?) {
        pinnedTitle = title
        navigationItem?.leftBarButtonItem = title == nil ? UIBarButtonItem(customView: titleView) : nil

        if let title {
            let pill = PolkadotPrizesNavTitlePill(text: title)
            pill.accessibilityId(AccessibilityID.Game.weeklyTitle)
            pinnedTitlePill = pill
            navigationItem?.style = .navigator
            navigationItem?.titleView = pill
        } else {
            pinnedTitlePill = nil
            navigationItem?.style = .editor
            navigationItem?.titleView = nil
        }

        refreshContactMenuPresentation()
        applyHeader()
    }
}

@available(iOS 26.0, *)
private extension LiquidGlassChatNavigationBarController {
    func applyClearBackground() {
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.titleTextAttributes = Self.titleTextAttributes

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.titleTextAttributes = Self.titleTextAttributes

        navigationItem?.standardAppearance = standard
        navigationItem?.scrollEdgeAppearance = scrollEdge
    }

    func applyHeader() {
        if pinnedTitle != nil {
            navigationItem?.title = nil
            navigationItem?.subtitle = nil
            return
        }
        navigationItem?.title = headerConfiguration?.username
        navigationItem?.subtitle = headerConfiguration?.additionalInfo
    }

    static var titleTextAttributes: [NSAttributedString.Key: Any] {
        [.font: UIFont.titleLarge, .foregroundColor: UIColor.fgPrimary]
    }

    func refreshContactMenuPresentation() {
        navigationItem?.titleMenuProvider = pinnedTitle == nil
            ? contactMenu.map { menu in { _ in menu } }
            : nil
        refreshRightBarButtonItems()
    }

    func refreshRightBarButtonItems() {
        var items: [UIBarButtonItem] = []
        if pinnedTitle != nil, let contactMenu {
            items.append(UIBarButtonItem(
                title: nil,
                image: UIImage(systemName: "ellipsis"),
                primaryAction: nil,
                menu: contactMenu
            ))
        }
        items.append(contentsOf: ChatCallBarButtons.make(for: callActions, onStartCall: onStartCall))
        navigationItem?.rightBarButtonItems = items.isEmpty ? nil : items
    }
}
