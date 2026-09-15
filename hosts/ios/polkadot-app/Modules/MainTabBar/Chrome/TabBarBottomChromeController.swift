import UIKit
import DesignSystem
import PolkadotUI
import SnapKit

final class TabBarBottomChromeController: UIViewController {
    private let glassContainer = DSGlassContainerView(
        shape: .rounded(32),
        tint: UIColor.bgSurfaceContainer
    )
    private let barView = DSTabBarView()
    private let backdropView = DSTabBarBackdropView()
    private let floatingWidgetContainerView = MainTabBarFloatingWidgetStackView()
    private let tabsPanelView = DSTabBarTabsPanelView()
    private let contentPanelView = DSTabBarContentPanelView()

    private var widgetControllers: [AppWidgetID: AppWidgetContentViewController] = [:]
    private weak var contentSafeAreaAdjustedViewController: UIViewController?
    private var floatingWidgetBottomConstraint: Constraint?
    private var glassContainerHeightConstraint: Constraint?

    private weak var appliedTabController: UIViewController?
    private weak var appliedContentController: UIViewController?

    private var appliedGlassContainerHeight: CGFloat = 0
    private var panelAnimator: UIViewPropertyAnimator?
    private var openPanel: TabBarPanelKind?
    private var pendingPanel: TabBarPanelKind?
    private var isApplyingPanel = false

    private var slots: [TabBarSlot] = []
    private var slotMap = TabBarSlotMap(slots: [])
    private var spaTabCount = 0
    private var badges: [Int: DSTabBarItem.Badge] = [:]
    private var selectedTabIndex = 0
    private weak var hostedPanelController: UIViewController?

    private lazy var foldController = TabBarFoldController(
        barView: barView,
        glassContainer: glassContainer,
        chromeBounds: { [unowned self] in view.bounds },
        grabZoneSink: { [weak self] zone in
            (self?.viewIfLoaded as? TabBarChromePassthroughView)?.foldGrabZone = zone
        },
        closePanel: { [weak self] in
            self?.setPanel(nil, animated: false)
        }
    )

    var onSelect: ((_ index: Int, _ isReselection: Bool) -> Void)?
    var onChipTapped: ((UUID) -> Void)?
    var onChipCloseRequested: ((UUID) -> Void)?
    var onPanelChanged: ((TabBarPanelKind?) -> Void)?

    private var occupiedHeight: CGFloat {
        guard TabBarVisibilityPolicy.contributesClearance(isTabRoot: foldController.isTabRoot) else {
            return view.safeAreaInsets.bottom
        }
        return DSTabBarView.preferredHeight()
    }

    private var contentClearance: CGFloat {
        max(0, occupiedHeight - view.safeAreaInsets.bottom)
    }

    private var availablePanelHeight: CGFloat {
        view.bounds.height
            - view.safeAreaInsets.top
            - DSTabBarView.preferredHeight()
    }

    override func loadView() {
        view = TabBarChromePassthroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        installGlassContainer()
        installBar()
        installFloatingWidgetContainer()
        installBackdrop()
        installTabsPanel()
        installContentPanel()
        installWidgetsIfNeeded()

        installOutsideTapRecognizer()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        updateLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateGlassContainerHeight(animator: nil)

        foldController.reapplyForWidthChange()
    }

    func setItems(_ slots: [TabBarSlot]) {
        self.slots = slots
        rebuildItems()
    }

    /// Indices crossing this boundary are tab-space; `TabBarSlotMap` converts them.
    func setSelectedIndex(_ tabIndex: Int) {
        selectedTabIndex = tabIndex

        guard let itemIndex = slotMap.itemIndex(forTabIndex: tabIndex) else {
            return
        }
        barView.selectedIndex = itemIndex
    }

    func setBadge(_ badge: DSTabBarItem.Badge?, at tabIndex: Int) {
        badges[tabIndex] = badge

        guard let itemIndex = slotMap.itemIndex(forTabIndex: tabIndex) else {
            return
        }
        barView.setBadge(badge, at: itemIndex)
    }

    func setSPATabs(_ chips: [DSTabBarChip], selected: UUID?) {
        if spaTabCount != chips.count {
            spaTabCount = chips.count
            rebuildItems()
        }
        tabsPanelView.setChips(chips, selected: selected)
        tabsPanelView.closeActionTitle = String(localized: .Common.close)

        if chips.isEmpty || availablePanelHeight <= 0 {
            if openPanel == .spaTabs {
                setPanel(nil, animated: true)
            }
            return
        }

        let animator = openPanel == .spaTabs ? makePanelAnimator() : nil
        updateGlassContainerHeight(animator: animator)
        animator?.startAnimation()
    }

    func setPanel(_ kind: TabBarPanelKind?, animated: Bool) {
        pendingPanel = nil

        let previousPanel = openPanel
        let animator = animated ? makePanelAnimator() : nil

        backdropView.setOpen(kind != nil, animator: animator)
        tabsPanelView.setOpen(kind == .spaTabs, animator: animator)
        contentPanelView.setOpen(kind?.contentAction != nil, animator: animator)
        (viewIfLoaded as? TabBarChromePassthroughView)?.isOutsideTapEnabled = kind != nil
        openPanel = kind
        updateActiveActionIndex()

        // Content is requested before the height is measured, so the open animates
        // straight to its final size and the scanner's capture session warms up during
        // the animation rather than after it. `isApplyingPanel` stops that push starting
        // a rival animator.
        if previousPanel != kind {
            isApplyingPanel = true
            onPanelChanged?(kind)
            isApplyingPanel = false
        }

        updateGlassContainerHeight(animator: animator)

        // The scanner's capture session must be released once the panel is gone, so the teardown
        // rides the same animator and still runs when there is none (a fold closes unanimated).
        if previousPanel?.contentAction != nil, kind?.contentAction == nil {
            let teardown = { [weak self] in self?.clearContentPanel() }
            if let animator {
                animator.addCompletion { _ in teardown() }
            } else {
                teardown()
            }
        }

        // `togglePanel` sets `pendingPanel` after this close returns, so the reopen is read at
        // completion time: a fold or another tap in between clears it and cancels the switch.
        if kind == nil, let animator {
            animator.addCompletion { [weak self] _ in
                guard let self, let pendingPanel else {
                    return
                }
                self.pendingPanel = nil
                setPanel(pendingPanel, animated: true)
            }
        }

        animator?.startAnimation()
    }

    /// Selecting a different action closes the open panel before opening the new one, so the
    /// change reads as a close followed by an open instead of a silent content swap.
    func togglePanel(_ kind: TabBarPanelKind) {
        guard let openPanel else {
            setPanel(kind, animated: true)
            return
        }

        guard openPanel != kind else {
            setPanel(nil, animated: true)
            return
        }

        setPanel(nil, animated: true)
        pendingPanel = kind
    }

    func setContentPanel(_ configuration: (any HashableContentConfiguration)?, for action: TabBarAction) {
        guard openPanel == .content(action) else {
            return
        }

        detachHostedController()
        contentPanelView.setConfiguration(configuration)
        resizeForContentPanel()
    }

    /// A camera controller needs its appearance callbacks, so it is hosted as a child rather than
    /// wrapped in a content view.
    func setContentController(_ controller: UIViewController?, for action: TabBarAction) {
        guard openPanel == .content(action) else {
            return
        }

        detachHostedController()

        if let controller {
            addChild(controller)
            contentPanelView.setHostedView(controller.view)
            controller.didMove(toParent: self)
            hostedPanelController = controller
        } else {
            contentPanelView.setHostedView(nil)
        }

        resizeForContentPanel()
    }

    func apply(
        _ context: TabBarChromeContext,
        animatingAlongside transitionCoordinator: UIViewControllerTransitionCoordinator? = nil
    ) {
        foldController.update(context: context)

        applyLayout(context, animatingAlongside: transitionCoordinator)
        foldController.refresh()
    }

    func applyLayout(
        _ context: TabBarChromeContext,
        animatingAlongside transitionCoordinator: UIViewControllerTransitionCoordinator? = nil
    ) {
        appliedTabController = context.tabController
        appliedContentController = context.contentController

        updateLayout(animatingAlongside: transitionCoordinator)
    }

    /// Resolves the visibility state a context would settle on, without committing it — used to
    /// drive the offset alongside an interactive navigation transition.
    func resolvedState(for context: TabBarChromeContext) -> TabBarVisibilityState {
        foldController.resolvedState(for: context)
    }

    /// Moves the chrome toward `state` in sync with an interactive transition. Unlike `apply(state:)`
    /// it runs no animator of its own, so the caller's transition coordinator owns the timing.
    func setInteractiveTarget(_ state: TabBarVisibilityState) {
        foldController.setInteractiveTarget(state)
    }

    func attachWidget(_ configuration: any HashableContentConfiguration, for id: AppWidgetID) {
        if let controller = widgetControllers[id] {
            controller.update(configuration: configuration)
            updateLayout()
            return
        }

        let controller = AppWidgetContentViewController(configuration: configuration)
        widgetControllers[id] = controller
        installWidget(controller)
    }

    func detachWidget(for id: AppWidgetID) {
        guard let controller = widgetControllers.removeValue(forKey: id) else {
            return
        }

        floatingWidgetContainerView.removeArrangedSubview(controller.view)
        controller.view.removeFromSuperview()

        updateLayout()
    }

    deinit {
        panelAnimator?.cancelInPlace()
    }
}

// MARK: - Bar items and panel content

private extension TabBarBottomChromeController {
    /// The SPA-tabs action is only shown while there are open apps, so the item list is derived
    /// rather than stored — and with it the map every index conversion goes through.
    func rebuildItems() {
        let effectiveSlots = spaTabCount > 0 ? slots : slots.filter { $0 != .action(.spaTabs) }
        slotMap = TabBarSlotMap(slots: effectiveSlots)

        barView.items = effectiveSlots.enumerated().map { itemIndex, slot in
            let badge = slotMap.tabIndex(forItemIndex: itemIndex).flatMap { badges[$0] }
            return slot.makeBarItem(badge: badge, spaTabCount: spaTabCount)
        }

        setSelectedIndex(selectedTabIndex)
        updateActiveActionIndex()
    }

    func updateActiveActionIndex() {
        barView.activeActionIndex = openPanel.flatMap { slotMap.itemIndex(for: $0.action) }
    }

    /// A push that arrives while `setPanel` is applying is already covered by the
    /// open animation.
    func resizeForContentPanel() {
        guard !isApplyingPanel, openPanel?.contentAction != nil else {
            return
        }

        let animator = makePanelAnimator()
        updateGlassContainerHeight(animator: animator)
        animator.startAnimation()
    }

    func clearContentPanel() {
        detachHostedController()
        contentPanelView.setHostedView(nil)
        contentPanelView.setConfiguration(nil)
    }

    func detachHostedController() {
        guard let controller = hostedPanelController else {
            return
        }

        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        hostedPanelController = nil
    }
}

// MARK: - Layout

private extension TabBarBottomChromeController {
    func installGlassContainer() {
        view.insertSubview(glassContainer, at: 0)
        glassContainer.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualTo(DSTabBarView.maxWidth)
            make.width.equalToSuperview().offset(-DSTabBarView.horizontalMargin * 2).priority(.high)
            make.bottom.equalToSuperview().offset(-DSTabBarView.bottomGap)
            glassContainerHeightConstraint = make.height.equalTo(DSTabBarView.capsuleHeight).constraint
        }
    }

    func installOutsideTapRecognizer() {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleOutsideTap))
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
    }

    @objc func handleOutsideTap() {
        guard !barView.isFolded else {
            foldController.setUserOverride(.shown, velocityX: 0)
            return
        }
        setPanel(nil, animated: true)
    }

    /// One animator drives the panel contents and the container resize so they cannot drift apart.
    func makePanelAnimator() -> UIViewPropertyAnimator {
        let previousPanelAnimator = panelAnimator
        panelAnimator = nil
        previousPanelAnimator?.cancelInPlace()

        let animator = UIViewPropertyAnimator(
            duration: DSTabBarTabsPanelView.openDuration,
            dampingRatio: DSTabBarTabsPanelView.openDampingRatio
        )
        animator.addCompletion { [weak self] _ in
            self?.panelAnimator = nil
        }
        panelAnimator = animator

        return animator
    }

    func updateGlassContainerHeight(animator: UIViewPropertyAnimator?) {
        let containerHeight: CGFloat =
            switch openPanel {
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
            self?.view.layoutIfNeeded()
        }
    }

    func installBar() {
        glassContainer.contentView.addSubview(barView)

        barView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview()
            make.height.equalTo(DSTabBarView.capsuleHeight)
        }

        barView.onFoldChangeRequested = { [weak self] folded, velocityX in
            self?.foldController.setUserOverride(folded ? .folded : .shown, velocityX: velocityX)
        }

        barView.onSelect = { [weak self] itemIndex, isReselection in
            guard let self, let tabIndex = slotMap.tabIndex(forItemIndex: itemIndex) else {
                return
            }
            onSelect?(tabIndex, isReselection)
        }

        barView.onActionTapped = { [weak self] itemIndex in
            guard let self, let action = slotMap.action(forItemIndex: itemIndex) else {
                return
            }
            togglePanel(action == .spaTabs ? .spaTabs : .content(action))
        }
    }

    func installFloatingWidgetContainer() {
        floatingWidgetContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(floatingWidgetContainerView, belowSubview: glassContainer)

        floatingWidgetContainerView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            floatingWidgetBottomConstraint = make.bottom.equalToSuperview().constraint
        }
    }

    /// Inserted at the bottom so both the tab content and the floating widgets sit behind it.
    func installBackdrop() {
        view.insertSubview(backdropView, at: 0)

        backdropView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func installTabsPanel() {
        glassContainer.contentView.insertSubview(tabsPanelView, belowSubview: barView)

        tabsPanelView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(barView.snp.top)
        }

        tabsPanelView.onChipTapped = { [weak self] id in self?.onChipTapped?(id) }
        tabsPanelView.onChipCloseRequested = { [weak self] id in self?.onChipCloseRequested?(id) }
    }

    func installContentPanel() {
        glassContainer.contentView.insertSubview(contentPanelView, belowSubview: barView)

        contentPanelView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(barView.snp.top)
        }
    }

    func installWidgetsIfNeeded() {
        widgetControllers.values.forEach(installWidget)
    }

    func installWidget(_ controller: UIViewController) {
        guard isViewLoaded else {
            return
        }

        controller.loadViewIfNeeded()
        floatingWidgetContainerView.addArrangedSubview(controller.view)

        updateLayout()
    }

    func hasAttachedWidget() -> Bool {
        !widgetControllers.isEmpty
    }

    func updateLayout(animatingAlongside transitionCoordinator: UIViewControllerTransitionCoordinator? = nil) {
        guard view.window != nil else {
            return
        }

        floatingWidgetBottomConstraint?.update(offset: -occupiedHeight)
        updateContentSafeAreaInset()

        guard hasAttachedWidget() else {
            return
        }

        animateFloatingWidgetConstraintChange(with: transitionCoordinator)
    }

    func updateContentSafeAreaInset() {
        let contentController = appliedContentController

        if contentSafeAreaAdjustedViewController !== contentController {
            contentSafeAreaAdjustedViewController?.additionalSafeAreaInsets.bottom = 0
        }

        let tabController = appliedTabController
        let barInset = contentClearance

        guard let contentController else {
            tabController?.additionalSafeAreaInsets.bottom = barInset
            contentSafeAreaAdjustedViewController = nil
            return
        }

        let widgetInset = floatingWidgetContentHeight()

        if contentController === tabController {
            contentController.additionalSafeAreaInsets.bottom = barInset + widgetInset
        } else {
            tabController?.additionalSafeAreaInsets.bottom = barInset
            contentController.additionalSafeAreaInsets.bottom = widgetInset
        }

        contentSafeAreaAdjustedViewController = widgetInset > 0 ? contentController : nil
    }

    func floatingWidgetContentHeight() -> CGFloat {
        guard hasAttachedWidget() else {
            return 0
        }

        let fittingWidth = max(floatingWidgetContainerView.bounds.width, view.bounds.width)
        let fittingSize = CGSize(
            width: fittingWidth,
            height: UIView.layoutFittingCompressedSize.height
        )
        let measuredSize = floatingWidgetContainerView.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        return max(floatingWidgetContainerView.bounds.height, measuredSize.height)
    }

    func animateFloatingWidgetConstraintChange(with transitionCoordinator: UIViewControllerTransitionCoordinator?) {
        view.setNeedsLayout()

        guard let transitionCoordinator else {
            view.layoutIfNeeded()
            return
        }

        transitionCoordinator.animate(
            alongsideTransition: { [weak self] _ in
                self?.view.layoutIfNeeded()
            }
        )
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TabBarBottomChromeController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === view
    }
}

private final class TabBarChromePassthroughView: UIView {
    var isOutsideTapEnabled = false
    var foldGrabZone: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)

        guard hitView === self else {
            return hitView
        }

        if !foldGrabZone.isEmpty, foldGrabZone.contains(point) {
            return self
        }
        return isOutsideTapEnabled ? self : nil
    }
}

private final class MainTabBarFloatingWidgetStackView: UIStackView {
    override init(frame: CGRect) {
        super.init(frame: frame)

        axis = .vertical
        alignment = .fill
        distribution = .fill
        spacing = 0
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}
