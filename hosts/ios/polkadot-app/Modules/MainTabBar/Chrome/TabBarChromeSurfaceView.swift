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

    var capsuleLayoutReference: UIView {
        glassContainer.contentView
    }

    var availablePanelHeight: CGFloat {
        bounds.height
            - safeAreaInsets.top
            - DSTabBarView.preferredHeight()
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

    func updateHeight(for kind: TabBarPanelKind?, animator: UIViewPropertyAnimator?) {
        let containerHeight: CGFloat =
            switch kind {
            case .spaTabs:
                tabsPanelView.preferredHeight(availableHeight: availablePanelHeight)
            case .content:
                contentPanelView.preferredHeight(availableHeight: availablePanelHeight)
            case nil:
                DSTabBarView.capsuleHeight
            }

        guard containerHeight != appliedGlassContainerHeight else {
            return
        }

        appliedGlassContainerHeight = containerHeight
        glassContainerHeightConstraint?.update(offset: containerHeight)

        animator?.addAnimations { [weak self] in
            self?.layoutIfNeeded()
        }
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
}

// MARK: - Layout

private extension TabBarChromeSurfaceView {
    func installGlassContainer() {
        insertSubview(glassContainer, at: 0)
        glassContainer.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualTo(DSTabBarView.maxWidth)
            make.width.equalToSuperview().offset(-DSTabBarView.horizontalMargin * 2).priority(.high)
            make.bottom.equalToSuperview().offset(-DSTabBarView.bottomGap)
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

    /// Both panels fill the glass above the capsule, which stays uncovered at the bottom.
    func installPanel(_ panel: UIView) {
        addSubview(panel)

        panel.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(glassContainer.contentView)
            make.bottom.equalTo(glassContainer.contentView).offset(-DSTabBarView.capsuleHeight)
        }
    }
}
