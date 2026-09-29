import Foundation
import UIKit

protocol AttestationOverlayControllerDelegate: AnyObject {
    func attestationControllerDidBeginAttestation(
        controller: AttestationOverlayController
    )
    func attestationController(
        controller: AttestationOverlayController,
        didChangeAttestation attested: Bool?
    )
}

final class AttestationOverlayController: NSObject {
    private var leftBounceDriver: ProgressDriver
    private var rightBounceDriver: ProgressDriver

    private var leftOverlayAnimator: OverlayAnimator?
    private var rightOverlayAnimator: OverlayAnimator?

    private weak var overlayView: AttestationOverlayView?

    private var lastLayoutSize: CGSize = .zero

    private var gestureForView: [UIView: UIPanGestureRecognizer] = [:]

    // Used to allow finish pan gesture exactly at view edge
    private var gestureSpeedMultiplier: CGFloat = 1
    private var initialGestureProgress: CGFloat = 0

    private var isRightScrubbingDueToLeftDrag = false

    // Used when decision is made to move opposite side
    private var gestureShouldDeriveBothSimultaneously: Bool = false

    // Used to increase Pan gesture update rate, to correctly calculate collisions with overlay animation
    private var displayLink: CADisplayLink?

    private var activePanGestureRecognizer: UIPanGestureRecognizer?

    private var selectedSide: Side?

    // used to determine whether animation should be applied
    private var animationDecisionSideState: Side?

    private var shouldHideOppositeArrowDuringPan: Bool = false

    private var userInteractionsAvailable: Bool {
        overlayView?.isUserInteractionEnabled == true
    }

    var userInteractionsAvailabilityState: Bool?

    weak var delegate: AttestationOverlayControllerDelegate?

    private var logger: Logger?

    // MARK: - Init

    init(
        view: AttestationOverlayView,
        logger: Logger? = Logger.shared
    ) {
        leftBounceDriver = BounceProgressDriver(target: view.leftArrowView)
        rightBounceDriver = BounceProgressDriver(target: view.rightArrowView)
        overlayView = view
        self.logger = logger
        super.init()

        installPanGesture(in: view.leftArrowGestureContainerView)
        installPanGesture(in: view.rightArrowGestureContainerView)
        installTapGesture(in: view)

        animateFinalisedDecision(to: nil, force: true)

        leftBounceDriver.start()
        rightBounceDriver.start()
    }

    // MARK: - Handlers

    func bind(attested: Bool?) {
        let side: Side? =
            if let attested {
                attested ? .left : .right
            } else {
                nil
            }

        guard selectedSide != side else { return }
        selectedSide = side

        // cancel gestures in the view
        gestureForView.values.forEach {
            cancelPanGesture($0)
        }

        animateFinalisedDecision(to: side)

        switch side {
        case .left:
            logger?.debug("[Swipe Attestation] Binding Left state")
            leftOverlayAnimator?.commitFill(duration: 0, timing: nil)
            rightOverlayAnimator?.cancelFill(duration: 0, timing: nil, force: true)
        case .right:
            logger?.debug("[Swipe Attestation] Binding Right state")
            rightOverlayAnimator?.commitFill(duration: 0, timing: nil)
            leftOverlayAnimator?.cancelFill(duration: 0, timing: nil, force: true)
        case nil:
            logger?.debug("[Swipe Attestation] Binding None state")
            leftOverlayAnimator?.cancelFill(duration: 0, timing: nil, force: true)
            rightOverlayAnimator?.cancelFill(duration: 0, timing: nil, force: true)
        }
    }

    func bind(discardTiming: AnimationSpan?) {
        if let discardTiming,
           selectedSide == nil {
            rightOverlayAnimator?.launch(with: discardTiming)
        } else {
            rightOverlayAnimator?.cancelAutomaticAnimation()
        }
    }

    // Should be called after superview layout subviews
    func overlayDidLayoutSubviews() {
        guard let overlayView else { return }
        let size = overlayView.bounds.size
        guard size != .zero else { return }

        if size != lastLayoutSize {
            lastLayoutSize = size
            setupPropertyAnimators()
        }
    }

    func overlayDidChangeUserInteractionEnabled() {
        guard let overlayView else { return }

        if userInteractionsAvailable == userInteractionsAvailabilityState {
            return
        }

        if !userInteractionsAvailable {
            stopBouncing()
        }

        userInteractionsAvailabilityState = userInteractionsAvailable

        animateDragIndicators(overlayView: overlayView, for: selectedSide)
        animateArrow(overlayView: overlayView, for: selectedSide, ignoreSide: [])
        if !userInteractionsAvailable, let activePanGestureRecognizer {
            cancelPanGesture(activePanGestureRecognizer)
        }
    }

    func stopBouncing() {
        leftBounceDriver.stop()
        rightBounceDriver.stop()

        leftBounceDriver.target?.animate(to: 0, duration: 1)
        rightBounceDriver.target?.animate(to: 0, duration: 1)

        guard let overlayView else { return }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) { [self] in
            arrowView(for: .left, overlayView: overlayView).alpha = 1
            arrowView(for: .right, overlayView: overlayView).alpha = 1
        }
    }

    func restartBouncing() {
        guard userInteractionsAvailable else { return }

        leftBounceDriver = BounceProgressDriver(target: leftBounceDriver.target)
        rightBounceDriver = BounceProgressDriver(target: rightBounceDriver.target)

        leftBounceDriver.start()
        rightBounceDriver.start()

        guard let overlayView else { return }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) { [self] in
            arrowView(for: .left, overlayView: overlayView).alpha = 0.5
            arrowView(for: .right, overlayView: overlayView).alpha = 0.5
        }
    }

    private func setupPropertyAnimators() {
        rightOverlayAnimator = createRightOverlayAnimator()
        leftOverlayAnimator = createLeftOverlayAnimator()

        rightOverlayAnimator?.delegate = self
    }

    private func createLeftOverlayAnimator() -> OverlayAnimator? {
        guard let overlayView else { return nil }
        let overlayWidth = overlayView.bounds.width
        return OverlayAnimator(
            animations: [
                OverlayAnimator.OverlayAnimationConfiguration(
                    view: overlayView.leftArrowView,
                    initialTransform: .identity,
                    finalTransform: .identity.translatedBy(x: overlayWidth, y: 0)
                ),
                OverlayAnimator.OverlayAnimationConfiguration(
                    view: overlayView.positiveAttestationView,
                    initialTransform: .identity.translatedBy(x: -overlayWidth, y: 0),
                    finalTransform: .identity
                )
            ], debugName: "Left"
        )
    }

    private func createRightOverlayAnimator() -> OverlayAnimator? {
        guard let overlayView else { return nil }
        let overlayWidth = overlayView.bounds.width
        return OverlayAnimator(
            animations: [
                OverlayAnimator.OverlayAnimationConfiguration(
                    view: overlayView.rightArrowView,
                    initialTransform: .identity,
                    finalTransform: .identity.translatedBy(x: -overlayWidth, y: 0)
                ),
                OverlayAnimator.OverlayAnimationConfiguration(
                    view: overlayView.negativeAttestationView,
                    initialTransform: .identity.translatedBy(x: overlayWidth, y: 0),
                    finalTransform: .identity
                )
            ], debugName: "Right"
        )
    }
}

private extension AttestationOverlayController {
    // MARK: - Constants

    enum Constants {
        // How far into the future to peek using velocity
        static let projectionHorizon: CGFloat = 0.3

        static let baseThreshold: CGFloat = 0.5
        static let commitHysteresis: CGFloat = 0.05

        // Velocity thresholds to detect a flick. (points per sec)
        static let flickPtsPerSec: CGFloat = 800

        // pan gesture animation duration
        // used static because animation will be finished using UISpringTimingParameters
        static let gestureAnimationDuration: TimeInterval = 0.2

        static let springTimingsVelocityRange: ClosedRange<CGFloat> = -15 ... 15
    }

    // MARK: - Side

    enum Side {
        case left
        case right

        var opposite: Side {
            switch self {
            case .left:
                .right
            case .right:
                .left
            }
        }

        var decisionImage: UIImage {
            switch self {
            case .left:
                .gameAttested
            case .right:
                .gameNotAttested
            }
        }

        var isAttested: Bool {
            self == .left
        }
    }

    func overlayAnimator(for side: Side) -> OverlayAnimator? {
        switch side {
        case .left:
            leftOverlayAnimator
        case .right:
            rightOverlayAnimator
        }
    }

    func side(for gestureView: UIView) -> Side? {
        guard let overlayView else {
            return nil
        }
        switch gestureView {
        case overlayView.leftArrowGestureContainerView:
            return .left
        case overlayView.rightArrowGestureContainerView:
            return .right
        default:
            assertionFailure()
            return nil
        }
    }

    func gestureRecognizer(for side: Side) -> UIPanGestureRecognizer? {
        guard let overlayView else { return nil }
        switch side {
        case .left:
            return gestureForView[overlayView.leftArrowGestureContainerView]
        case .right:
            return gestureForView[overlayView.rightArrowGestureContainerView]
        }
    }

    func side(for animator: OverlayAnimator) -> Side? {
        if animator === leftOverlayAnimator {
            .left
        } else if animator === rightOverlayAnimator {
            .right
        } else {
            nil
        }
    }

    // MARK: - Display Link

    func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc func handleTick() {
        guard let gesture = activePanGestureRecognizer,
              let view = gesture.view,
              let side = side(for: view),
              let overlayView
        else {
            return
        }

        let pointsPerFullRange = overlayView.bounds.width
        let translationInverted = side == .right

        guard pointsPerFullRange > 0 else {
            return
        }

        let translation = gesture.translation(in: view)
        let translationX = translationInverted ? -translation.x : translation.x

        let progress = (initialGestureProgress + (translationX / pointsPerFullRange * gestureSpeedMultiplier))
            .clamped(to: 0 ... 1)

        handleAttestationPanUpdate(
            side: side,
            progress: progress,
            pointsPerFullRange: pointsPerFullRange,
            overlayView: overlayView
        )
    }

    // MARK: - Pan Handlers

    func installPanGesture(in view: UIView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        view.addGestureRecognizer(pan)
        gestureForView[view] = pan
    }

    func installTapGesture(in view: UIView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        gestureForView.values.forEach { pan in
            tap.require(toFail: pan)
        }
        view.addGestureRecognizer(tap)
    }

    @objc func handleTap(_: UITapGestureRecognizer) {
        guard userInteractionsAvailable else { return }

        if selectedSide == nil {
            bind(attested: true)
            delegate?.attestationController(controller: self, didChangeAttestation: true)
        } else {
            bind(attested: nil)
            delegate?.attestationController(controller: self, didChangeAttestation: nil)
        }
    }

    func cancelPanGesture(_ pan: UIPanGestureRecognizer?) {
        guard let pan else { return }
        pan.isEnabled = false
        pan.isEnabled = true
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view,
              let side = side(for: view),
              let overlayView
        else {
            return
        }

        let pointsPerFullRange = overlayView.bounds.width
        let translationInverted = side == .right

        guard pointsPerFullRange > 0 else {
            return
        }

        switch gesture.state {
        case .began:
            let initialProgress = overlayAnimator(for: side)?.progress ?? 0
            let progressLeft = 1 - initialProgress
            let pointsLeft = progressLeft * pointsPerFullRange

            let initialPoint = gesture.location(in: view)
            let fingerToEdgeDistance = translationInverted
                ? view.bounds.width - initialPoint.x
                : initialPoint.x

            let availableGestureWidth = pointsPerFullRange - fingerToEdgeDistance

            gestureSpeedMultiplier = pointsLeft / availableGestureWidth
            initialGestureProgress = initialProgress
            activePanGestureRecognizer = gesture
            gestureShouldDeriveBothSimultaneously = selectedSide != nil
            shouldHideOppositeArrowDuringPan = selectedSide == nil &&
                overlayAnimator(for: side.opposite)?.hasStarted == false

            logger?.debug("[Swipe Attestation] Gesture side: \(side)")
            logger?.debug("[Swipe Attestation] Initial progress: \(initialProgress)")
            logger?.debug("[Swipe Attestation] Gesture speed multiplier: \(gestureSpeedMultiplier)")
            logger?.debug(
                "[Swipe Attestation] Gesture should derive simultaneously: \(gestureShouldDeriveBothSimultaneously)"
            )

            handleAttestationPanStart(side: side)

            delegate?.attestationControllerDidBeginAttestation(controller: self)

            startDisplayLink()
            // handle first tick instantly
            handleTick()

        case .changed:
            // gesture location is handled by Display link
            break

        case .ended,
             .cancelled,
             .failed:
            logger?.debug("[Swipe Attestation] Gesture state: \(gesture.state)")

            stopDisplayLink()

            handleAttestationPanEnd(
                side: side,
                pan: gesture,
                pointsPerFullRange: pointsPerFullRange
            )

            activePanGestureRecognizer = nil
            gestureShouldDeriveBothSimultaneously = false

        default:
            break
        }
    }

    func handleAttestationPanStart(side: Side) {
        // reset completions
        leftOverlayAnimator?.setCompletion {}
        rightOverlayAnimator?.setCompletion {}

        stopBouncing()

        animateFinalisedDecision(to: nil, ignoreSide: [side.opposite])
        if gestureShouldDeriveBothSimultaneously, let overlayView {
            UIView.performWithoutAnimation {
                animateArrow(overlayView: overlayView, for: side.opposite, ignoreSide: [])
            }
        }

        bringViewsToFront(for: side)

        overlayAnimator(for: side)?.panBegan()
        if gestureShouldDeriveBothSimultaneously {
            overlayAnimator(for: side.opposite)?.panBegan()
        }
    }

    func handleAttestationPanUpdate(
        side: Side,
        progress: CGFloat,
        pointsPerFullRange _: CGFloat,
        overlayView: AttestationOverlayView
    ) {
        let invertedProgress = 1 - progress

        // Animate arrow expand with pan progress
        let arrowView = arrowView(for: side, overlayView: overlayView)
        let arrowGrowMultiplier: CGFloat = 1.2
        arrowView.progress = progress * arrowGrowMultiplier

        switch side {
        case .left:
            leftOverlayAnimator?.panChanged(progress: progress)
            if gestureShouldDeriveBothSimultaneously {
                rightOverlayAnimator?.panChanged(progress: invertedProgress)
            } else {
                handleRightOverlayAnimation(progress)
            }

        case .right:
            rightOverlayAnimator?.panChanged(progress: progress)
            if gestureShouldDeriveBothSimultaneously {
                leftOverlayAnimator?.panChanged(progress: invertedProgress)
            }
        }

        if shouldHideOppositeArrowDuringPan {
            let oppositeArrowView = self.arrowView(for: side.opposite, overlayView: overlayView)
            let hideMultiplier = 2.0
            oppositeArrowView.alpha = invertedProgress * hideMultiplier
        }
    }

    func handleAttestationPanEnd(
        side: Side,
        pan: UIPanGestureRecognizer,
        pointsPerFullRange: CGFloat
    ) {
        guard pointsPerFullRange > 0,
              let gestureView = pan.view,
              let overlayView else {
            return
        }

        guard let gestureSideAnimator = overlayAnimator(for: side),
              let otherSideAnimator = overlayAnimator(for: side.opposite) else {
            return
        }

        gestureSideAnimator.panEnded()

        let progress = gestureSideAnimator.progress

        let velocityX = pan.velocity(in: gestureView).x
        let signedVelocity = (side == .right) ? -velocityX : velocityX

        let projectedProgress = projectedProgress(
            progress,
            signedVelocityX: signedVelocity,
            pointsPerFullRange: pointsPerFullRange,
            projectionTime: Constants.projectionHorizon
        )

        let gestureContainerWidth = gestureView.bounds.width

        if side == .left, isRightScrubbingDueToLeftDrag {
            rightOverlayAnimator?.panEnded()
            isRightScrubbingDueToLeftDrag = false
        }
        logger?.debug(
            """
            [Swipe Attestation] Projected progress: \(projectedProgress), \nvelocity: \(signedVelocity), \nprogress: \(
                progress
            )
            """
        )

        let arrowView = arrowView(for: side, overlayView: overlayView)
        arrowView.animate(to: 0, duration: 0.3)

        if shouldCommit(
            state: pan.state,
            projected: projectedProgress,
            progressVelocity: signedVelocity
        ) {
            let duration = Constants.gestureAnimationDuration

            let finishTiming = finishInteraction(
                currentProgress: progress,
                target: 1,
                velocityX: velocityX,
                containerWidth: gestureContainerWidth
            )
            let cancelTiming = finishInteraction(
                currentProgress: progress,
                target: 0,
                velocityX: velocityX,
                containerWidth: gestureContainerWidth
            )
            logger?.debug("[Swipe Attestation] Should commit, duration: \(duration)")

            gestureSideAnimator.commitFill(duration: duration, timing: finishTiming)
            otherSideAnimator.cancelFill(duration: duration, timing: cancelTiming, force: true)

            selectedSide = side
            notifyDelegateAboutSideSelection()

            gestureSideAnimator.setCompletion { [weak self] in
                self?.animateFinalisedDecision(to: side)
            }
        } else {
            logger?.debug("[Swipe Attestation] Should not commit")
            let timing = finishInteraction(
                currentProgress: progress,
                target: 0,
                velocityX: velocityX,
                containerWidth: gestureContainerWidth
            )
            let cancelDuration = Constants.gestureAnimationDuration
            gestureSideAnimator.cancelFill(duration: cancelDuration, timing: timing, force: false)

            if gestureShouldDeriveBothSimultaneously {
                otherSideAnimator.panEnded()
                otherSideAnimator.commitFill(duration: cancelDuration, timing: timing)
                selectedSide = side.opposite
                notifyDelegateAboutSideSelection()
            }

            // reapply selection
            if let selectedSide {
                gestureSideAnimator.setCompletion { [weak self] in
                    self?.animateFinalisedDecision(to: selectedSide)
                }
            } else {
                animateArrow(overlayView: overlayView, for: nil, ignoreSide: [])
            }
        }
    }

    func handleRightOverlayAnimation(_ progress: CGFloat) {
        let rightProgress = rightOverlayAnimator?.progress ?? 0
        if rightProgress + progress >= 1 {
            if !isRightScrubbingDueToLeftDrag {
                rightOverlayAnimator?.panBegan()
                isRightScrubbingDueToLeftDrag = true
            }
            rightOverlayAnimator?.panChanged(progress: (1 - progress).clamped(to: 0 ... 1))
        } else {
            if isRightScrubbingDueToLeftDrag {
                rightOverlayAnimator?.panEnded()
                isRightScrubbingDueToLeftDrag = false
            }
        }
    }

    func projectedProgress(
        _ current: CGFloat,
        signedVelocityX: CGFloat,
        pointsPerFullRange: CGFloat,
        projectionTime: CGFloat
    ) -> CGFloat {
        let addition = (signedVelocityX / pointsPerFullRange) * projectionTime
        return current + addition
    }

    func shouldCommit(
        state: UIGestureRecognizer.State,
        projected: CGFloat,
        progressVelocity: CGFloat
    ) -> Bool {
        switch state {
        case .cancelled,
             .failed:
            return false
        default:
            break
        }

        let movingTowardCommit = progressVelocity > 0

        let base = Constants.baseThreshold
        let band = Constants.commitHysteresis
        let lower = max(0, base - band)
        let upper = min(1, base + band)

        let isFlick = abs(progressVelocity) >= Constants.flickPtsPerSec
        if isFlick {
            logger?.debug("[Swipe Attestation] Flick detected, movingTowardCommit: \(movingTowardCommit)")
            return movingTowardCommit
        }

        if projected >= upper {
            logger?.debug("[Swipe Attestation] projected >= upper")
            return true
        }

        if projected <= lower {
            logger?.debug("[Swipe Attestation] projected <= lower")
            return false
        }

        return projected >= base
    }

    func finishInteraction(
        currentProgress: CGFloat,
        target: CGFloat,
        velocityX: CGFloat,
        containerWidth: CGFloat
    ) -> UISpringTimingParameters? {
        let velocityX = abs(velocityX)
        let remainingProgress = max(abs(target - currentProgress), 0.0001)
        let springInitialVelocity = ((velocityX / max(containerWidth, 1)) / remainingProgress)
            .clamped(to: Constants.springTimingsVelocityRange)

        logger?.debug("[Swipe Attestation] springInitialVelocity \(springInitialVelocity)")

        return UISpringTimingParameters(
            dampingRatio: 0.9,
            initialVelocity: CGVector(dx: springInitialVelocity, dy: 0)
        )
    }

    func bringViewsToFront(for side: Side) {
        guard let overlayView else { return }
        switch side {
        case .left:
            overlayView.bringSubviewToFront(overlayView.positiveAttestationView)
            overlayView.bringSubviewToFront(overlayView.leftArrowGestureContainerView)
            overlayView.bringSubviewToFront(overlayView.leftArrowDragIndicator)

        case .right:
            overlayView.bringSubviewToFront(overlayView.negativeAttestationView)
            overlayView.bringSubviewToFront(overlayView.rightArrowGestureContainerView)
            overlayView.bringSubviewToFront(overlayView.rightArrowDragIndicator)
        }
    }

    func notifyDelegateAboutSideSelection() {
        delegate?.attestationController(
            controller: self,
            didChangeAttestation: selectedSide?.isAttested
        )
    }

    func animateFinalisedDecision(
        to side: Side?,
        force: Bool = false,
        ignoreSide: Set<Side> = []
    ) {
        guard let overlayView else { return }

        // should be animated anyway because there might be other source of trues for this arrow
        animateArrow(overlayView: overlayView, for: side, ignoreSide: ignoreSide)

        if !force, animationDecisionSideState == side {
            return
        }
        animationDecisionSideState = side

        if let side {
            bringViewsToFront(for: side.opposite)
        }

        animateDragIndicators(overlayView: overlayView, for: side)
        animateDecisionImage(overlayView: overlayView, for: side)
    }

    func animateArrow(
        overlayView: AttestationOverlayView,
        for side: Side?,
        ignoreSide: Set<Side>
    ) {
        logger?.debug("[AttestationOverlayController] Animating arrow for \(String(describing: side))")
        if !userInteractionsAvailable {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) {
                if !ignoreSide.contains(.left) {
                    overlayView.leftArrowView.alpha = 0
                }
                if !ignoreSide.contains(.right) {
                    overlayView.rightArrowView.alpha = 0
                }
            }
        } else if let side {
            // Handle opposite site
            let oppositeArrowView = arrowView(for: side.opposite, overlayView: overlayView)
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) {
                oppositeArrowView.alpha = 1
            }

            // Handle main side
            guard !ignoreSide.contains(side) else { return }
            let arrowView = arrowView(for: side, overlayView: overlayView)
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) {
                arrowView.alpha = 0
            }
        } else {
            // no transform animation expected
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) {
                if !ignoreSide.contains(.left) {
                    overlayView.leftArrowView.alpha = 1
                }
                if !ignoreSide.contains(.right) {
                    overlayView.rightArrowView.alpha = 1
                }
            }
        }
    }

    func animateDragIndicators(
        overlayView: AttestationOverlayView,
        for side: Side?
    ) {
        if userInteractionsAvailable, let side = side?.opposite {
            let dragIndicator = dragIndictorView(for: side, overlayView: overlayView)
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) {
                dragIndicator.alpha = 1
                dragIndicator.transform = .identity
            }
        } else {
            let offset: CGFloat = overlayView.leftArrowDragIndicator.bounds.width
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState]) {
                overlayView.leftArrowDragIndicator.alpha = 0
                overlayView.leftArrowDragIndicator.transform = .identity.translatedBy(x: -offset, y: 0)

                overlayView.rightArrowDragIndicator.alpha = 0
                overlayView.rightArrowDragIndicator.transform = .identity.translatedBy(x: offset, y: 0)
            }
        }
    }

    func arrowView(for side: Side, overlayView: AttestationOverlayView) -> ScrubbableArrowView {
        switch side {
        case .left:
            overlayView.leftArrowView
        case .right:
            overlayView.rightArrowView
        }
    }

    func dragIndictorView(for side: Side, overlayView: AttestationOverlayView) -> UIView {
        switch side {
        case .left:
            overlayView.leftArrowDragIndicator
        case .right:
            overlayView.rightArrowDragIndicator
        }
    }

    func animateDecisionImage(
        overlayView: AttestationOverlayView,
        for side: Side?
    ) {
        let imageView = overlayView.decisionImageView

        let decisionImage = side?.decisionImage
        if let decisionImage {
            imageView.image = decisionImage
        }

        let appearAnimation = side != nil

        let minScale: CGFloat = 0.2

        let initialTransform: CGAffineTransform = appearAnimation
            ? .identity.scaledBy(x: minScale, y: minScale)
            : .identity
        let finalTransform: CGAffineTransform = appearAnimation
            ? .identity
            : .identity.scaledBy(x: minScale, y: minScale)

        let initialAlpha: CGFloat = appearAnimation ? 0 : 1
        let finalAlpha: CGFloat = appearAnimation ? 1 : 0

        imageView.superview?.bringSubviewToFront(imageView)
        imageView.layer.removeAllAnimations()

        UIView.performWithoutAnimation {
            imageView.transform = initialTransform
            imageView.alpha = initialAlpha
        }

        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.8,
            options: [.allowUserInteraction, .curveEaseInOut, .beginFromCurrentState]
        ) {
            imageView.transform = finalTransform
            imageView.alpha = finalAlpha
        }
    }
}

extension AttestationOverlayController: OverlayAnimatorDelegate {
    func overlayAnimatorDidEnterNonInterruptiblePhase(_: OverlayAnimator) {
        gestureForView.values.forEach {
            cancelPanGesture($0)
        }
    }

    func overlayAnimatorDidStartDelayedAnimation(_: OverlayAnimator) {
        // cancel arrow modification
        if shouldHideOppositeArrowDuringPan {
            shouldHideOppositeArrowDuringPan = false
            guard let overlayView else { return }
            animateArrow(overlayView: overlayView, for: nil, ignoreSide: [])
        }

        stopBouncing()

        delegate?.attestationControllerDidBeginAttestation(controller: self)
    }

    func overlayAnimatorDidFinishAnimation(_ animator: OverlayAnimator) {
        guard let side = side(for: animator) else {
            return
        }
        selectedSide = side
        notifyDelegateAboutSideSelection()

        animateFinalisedDecision(to: side)
    }
}

extension AttestationOverlayController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UITapGestureRecognizer {
            return userInteractionsAvailable
        }

        guard let view = gestureRecognizer.view,
              let side = side(for: view) else {
            return false
        }

        if selectedSide == side {
            return false
        }

        return true
    }
}
