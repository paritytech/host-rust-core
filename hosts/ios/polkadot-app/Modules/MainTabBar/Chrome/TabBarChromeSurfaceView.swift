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

    private weak var barView: DSTabBarView?
    private var glassContainerHeightConstraint: Constraint?
    private var appliedGlassContainerHeight: CGFloat = 0
    private var glassContainerBottomConstraint: Constraint?
    private var barBottomConstraint: Constraint?
    private var isPanelTrackingKeyboard = false
    private var isContentFilling = false

    /// At rest the guide sits on the view's bottom edge, so the chrome only clears the home
    /// indicator gap. Over the keys the whole chrome rises as one block, sunk by half a capsule
    /// so the capsule's lower half hides behind them.
    private static let restingBottomOffset = -DSTabBarView.bottomGap
    private static let keyboardBottomOffset = DSTabBarView.capsuleHeight / 2

    var availablePanelHeight: CGFloat {
        let occupiedHeight: CGFloat =
            if isPanelTrackingKeyboard {
                bounds.height - keyboardLayoutGuide.layoutFrame.minY - Self.keyboardBottomOffset
            } else {
                DSTabBarView.preferredHeight()
            }

        return bounds.height - topInset - occupiedHeight
    }

    /// The chain-status strip reaches the chrome as an additional top safe-area inset. A filling
    /// panel passes under it and stops at the status bar; every other state keeps clear of it.
    private var topInset: CGFloat {
        guard isContentFilling, let windowInset = window?.safeAreaInsets.top else {
            return safeAreaInsets.top
        }
        return windowInset
    }

    var onChipTapped: ((UUID) -> Void)?
    var onChipCloseRequested: ((UUID) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Without the safe area the guide rests on the view's bottom edge, so one anchor per view
        // spans both states and only its offset changes when the keys come up.
        keyboardLayoutGuide.usesBottomSafeArea = false

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

    func addBar(_ bar: DSTabBarView) {
        addSubview(bar)
        barView = bar

        bar.snp.makeConstraints { make in
            make.leading.trailing.equalTo(glassContainer.contentView)
            make.height.equalTo(DSTabBarView.capsuleHeight)
            barBottomConstraint = make.bottom.equalTo(keyboardLayoutGuide.snp.top)
                .offset(Self.restingBottomOffset).constraint
        }
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

        let offset = tracking ? Self.keyboardBottomOffset : Self.restingBottomOffset
        glassContainerBottomConstraint?.update(offset: offset)
        barBottomConstraint?.update(offset: offset)
        barView?.setKeyboardShadowVisible(tracking)
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
            glassContainerBottomConstraint = make.bottom.equalTo(keyboardLayoutGuide.snp.top)
                .offset(Self.restingBottomOffset).constraint
            glassContainerHeightConstraint = make.height.equalTo(DSTabBarView.capsuleHeight).constraint
        }
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
    /// and always stop a capsule short of the glass bottom, at rest and over the keyboard alike.
    func installPanel(_ panel: UIView) {
        addSubview(panel)

        panel.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(glassContainer.contentView)
            make.bottom.equalTo(glassContainer.contentView)
                .offset(-DSTabBarView.capsuleHeight)
        }
    }
}
