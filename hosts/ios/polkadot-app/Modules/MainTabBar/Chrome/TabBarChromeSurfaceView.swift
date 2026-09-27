import UIKit
import DesignSystem
import PolkadotUI
import SnapKit

final class TabBarChromeSurfaceView: UIView {
    private let glassContainer = DSGlassContainerView(
        shape: .rounded(32),
        tint: nil
    )
    private let tabsPanelView = DSTabBarTabsPanelView()
    private let contentPanelView = DSTabBarContentPanelView()

    private var glassContainerHeightConstraint: Constraint?
    private var appliedGlassContainerHeight: CGFloat = 0
    private var glassContainerBottomSuperviewConstraint: Constraint?
    private var glassContainerBottomKeyboardConstraint: Constraint?
    private var panelBottomConstraints: [Constraint] = []
    private var isPanelTrackingKeyboard = false
    private var isContentFilling = false

    var capsuleLayoutReference: UIView {
        glassContainer.contentView
    }

    var availablePanelHeight: CGFloat {
        let occupiedHeight: CGFloat =
            if isPanelTrackingKeyboard {
                bounds.height - keyboardLayoutGuide.layoutFrame.minY
            } else {
                DSTabBarView.preferredHeight()
            }

        return bounds.height - safeAreaInsets.top - occupiedHeight
    }

    var onChipTapped: ((UUID) -> Void)?
    var onChipCloseRequested: ((UUID) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        installGlassContainer()
        installTabsPanel()
        installContentPanel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }

    func addBar(_ bar: UIView) {
        addSubview(bar)
    }

    func setPanelsOpen(_ kind: TabBarPanelKind?, animator: UIViewPropertyAnimator?) {
        tabsPanelView.setOpen(kind == .spaTabs, animator: animator)
        contentPanelView.setOpen(kind?.contentAction != nil, animator: animator)
    }

    @discardableResult
    func updateHeight(for kind: TabBarPanelKind?, animator: UIViewPropertyAnimator?) -> Bool {
        let containerHeight: CGFloat =
            switch kind {
            case .spaTabs:
                tabsPanelView.preferredHeight(availableHeight: availablePanelHeight)
            case .content:
                // While a search is active the content fills the space above the keys or the
                // tab bar instead of fitting its rows.
                if isContentFilling {
                    max(0, availablePanelHeight)
                } else {
                    contentPanelView.preferredHeight(availableHeight: availablePanelHeight)
                }
            case nil:
                DSTabBarView.capsuleHeight
            }

        guard containerHeight != appliedGlassContainerHeight else {
            return false
        }

        appliedGlassContainerHeight = containerHeight
        glassContainerHeightConstraint?.update(offset: containerHeight)

        animator?.addAnimations { [weak self] in
            self?.layoutIfNeeded()
        }

        return true
    }

    func setChips(_ chips: [DSTabBarChip], selected: UUID?, closeActionTitle: String) {
        tabsPanelView.setChips(chips, selected: selected)
        tabsPanelView.closeActionTitle = closeActionTitle
    }

    func setContentConfiguration(_ configuration: (any HashableContentConfiguration)?) {
        contentPanelView.setConfiguration(configuration)
    }

    func setContentHostedView(_ view: UIView?) {
        contentPanelView.setHostedView(view)
    }

    func setPanelTracksKeyboard(_ tracking: Bool) {
        guard tracking != isPanelTrackingKeyboard else {
            return
        }

        isPanelTrackingKeyboard = tracking

        if tracking {
            glassContainerBottomSuperviewConstraint?.deactivate()
            glassContainerBottomKeyboardConstraint?.activate()
            panelBottomConstraints.forEach { $0.update(offset: 0) }
        } else {
            glassContainerBottomKeyboardConstraint?.deactivate()
            glassContainerBottomSuperviewConstraint?.activate()
            panelBottomConstraints.forEach { $0.update(offset: -DSTabBarView.capsuleHeight) }
        }
    }

    /// While a search is active the content panel fills the available height instead of fitting its rows.
    func setContentFillsAvailableHeight(_ fills: Bool) {
        isContentFilling = fills
    }
}

// MARK: - Layout

private extension TabBarChromeSurfaceView {
    func installGlassContainer() {
        insertSubview(glassContainer, at: 0)
        glassContainer.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualTo(DSTabBarView.maxWidth)
            make.width.equalToSuperview().offset(-DSTabBarView.horizontalMargin * 2).priority(.high)
            glassContainerBottomSuperviewConstraint = make.bottom.equalToSuperview()
                .offset(-DSTabBarView.bottomGap).constraint
            glassContainerHeightConstraint = make.height.equalTo(DSTabBarView.capsuleHeight).constraint
        }

        // Resting constraint offsets the home indicator; keyboard tracking sits flush on the keys
        glassContainer.snp.makeConstraints { make in
            glassContainerBottomKeyboardConstraint = make.bottom.equalTo(keyboardLayoutGuide.snp.top).constraint
        }
        glassContainerBottomKeyboardConstraint?.deactivate()
    }

    func installTabsPanel() {
        installPanel(tabsPanelView)

        tabsPanelView.onChipTapped = { [weak self] id in self?.onChipTapped?(id) }
        tabsPanelView.onChipCloseRequested = { [weak self] id in self?.onChipCloseRequested?(id) }
    }

    func installContentPanel() {
        installPanel(contentPanelView)
    }

    /// Both panels fill the glass above the capsule, which stays uncovered at the bottom,
    /// and fill it edge to edge while the glass tracks the keyboard and the capsule is hidden.
    func installPanel(_ panel: UIView) {
        addSubview(panel)

        panel.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(glassContainer.contentView)
            panelBottomConstraints.append(
                make.bottom.equalTo(glassContainer.contentView)
                    .offset(-DSTabBarView.capsuleHeight).constraint
            )
        }
    }
}
