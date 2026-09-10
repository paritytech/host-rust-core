import UIKit

struct AnimationSpan: Equatable {
    let startsAt: CFTimeInterval
    let duration: TimeInterval
}

protocol OverlayAnimatorDelegate: AnyObject {
    func overlayAnimatorDidStartDelayedAnimation(_ animator: OverlayAnimator)
    func overlayAnimatorDidEnterNonInterruptiblePhase(_ animator: OverlayAnimator)
    func overlayAnimatorDidFinishAnimation(_ animator: OverlayAnimator)
}

final class OverlayAnimator {
    struct OverlayAnimationConfiguration {
        // view to animate
        weak var view: UIView?

        let initialTransform: CGAffineTransform
        let finalTransform: CGAffineTransform
    }

    // MARK: - Constants

    private enum Constants {
        /// Below this duration we "snap" instead of animating.
        static let minimumAnimateDuration: TimeInterval = 0.001

        static let lockInteractionThreshold: TimeInterval = 0.35

        /// Used to create paused animator, with non zero duration
        static let defaultDuration: TimeInterval = 0.5
    }

    // MARK: - Inputs

    private var animations: [OverlayAnimationConfiguration] = []

    // MARK: - State

    private var propertyAnimator: UIViewPropertyAnimator?
    private var invertedAnimator: UIViewPropertyAnimator?

    // flag used to configure initial state of animator once
    private var overlayAnimatorConfigured: Bool = false
    private var overlayTiming: AnimationSpan?
    private var startTimer: Timer?
    private(set) var hasStarted = false
    private var hasLockedInteraction = false

    private var committedProgress: CGFloat = 0 {
        didSet {
            print("[Swipe Attestation] side \(debugName) committedProgress update: \(committedProgress)")
        }
    }

    var progress: CGFloat {
        if let progress = propertyAnimator?.fractionComplete {
            return progress
        }
        if let invertedProgress = invertedAnimator?.fractionComplete {
            return 1 - invertedProgress
        }
        return committedProgress
    }

    weak var delegate: OverlayAnimatorDelegate?

    let debugName: String

    private(set) var completionAction: (() -> Void)?

    // MARK: - Init

    init(animations: [OverlayAnimationConfiguration], debugName: String) {
        self.animations = animations
        self.debugName = debugName
        animations.forEach {
            $0.view?.transform = $0.initialTransform
        }
    }

    deinit {
        invalidateStartTimer()
        propertyAnimator?.stopAnimation(true)
    }

    // MARK: - Public Handlers

    func setCompletion(action: @escaping () -> Void) {
        completionAction = { [weak self] in
            action()
            self?.completionAction = nil
        }
    }

    /// Schedule the overlay to end at `startsAt + duration`.
    func launch(with overlayTiming: AnimationSpan) {
        if self.overlayTiming != nil {
            print("[Swipe Attestation] Lunch ignored, for \(overlayTiming), previous should be cancelled before")
            return
        }

        print("[Swipe Attestation] Lunch scheduled for \(overlayTiming)")

        self.overlayTiming = overlayTiming
        hasStarted = false
        hasLockedInteraction = false
        overlayAnimatorConfigured = false
        cancelCurrentAnimator(preservePresentation: true)
        armStartTimerOrStartNow()
    }

    func cancelAutomaticAnimation() {
        guard overlayTiming != nil else {
            // should be nothing to cancel
            return
        }

        overlayTiming = nil
        hasStarted = false
        invalidateStartTimer()

        hasLockedInteraction = false
        overlayAnimatorConfigured = false
        cancelCurrentAnimator(preservePresentation: false)
    }

    // to remove
    func panBegan() {
        guard !hasLockedInteraction else { return }

        if overlayTiming == nil {
            cancelCurrentAnimator(preservePresentation: true)
        }

        ensureAnimatorReadyForScrub()

        propertyAnimator?.pauseAnimation()
    }

    func panChanged(progress: CGFloat) {
        print(
            "[Swipe Attestation] side \(debugName): pan changed: \(progress), hasLockedInteraction: \(hasLockedInteraction)"
        )
        lockIfNearEnd()

        guard !hasLockedInteraction else { return }
        ensureAnimatorReadyForScrub()
        propertyAnimator?.fractionComplete = progress
        committedProgress = progress
    }

    /// User released — resume so we still finish at the fixed deadline.
    func panEnded() {
        print("[Swipe Attestation] side \(debugName): Pan ended")
        armStartTimerOrStartNow()
    }

    func commitFill(duration: TimeInterval, timing: UISpringTimingParameters?) {
        print(
            "[Swipe Attestation] side \(debugName): Commit fill, hasLockedInteraction: \(hasLockedInteraction), progress: \(progress), duration: \(duration)"
        )
        guard !hasLockedInteraction else { return }

        let animations = animations
        let currentProgress = progress
        cancelCurrentAnimator(preservePresentation: true)

        // cancel overlay animation
        overlayTiming = nil
        hasStarted = false
        invalidateStartTimer()

        UIView.performWithoutAnimation {
            animations.forEach { $0.view?.transform = $0.initialTransform }
        }

        let animator =
            if let timing {
                UIViewPropertyAnimator(duration: duration, timingParameters: timing)
            } else {
                UIViewPropertyAnimator(duration: duration, curve: .linear)
            }

        animator.addAnimations {
            animations.forEach { $0.view?.transform = $0.finalTransform }
        }
        animator.addCompletion { [weak self] _ in
            self?.committedProgress = 1
            self?.completionAction?()
        }
        animator.fractionComplete = currentProgress

        propertyAnimator = animator
        animator.pauseAnimation()

        animator.continueAnimation(
            withTimingParameters: timing,
            durationFactor: 1
        )
    }

    /// Cancel and animate back to the off-screen transform.
    ///
    /// `force` - Specify `true` if auto animation state should be ignored and discarded if exist
    func cancelFill(
        duration: TimeInterval,
        timing: UISpringTimingParameters?,
        force: Bool
    ) {
        print("[Swipe Attestation] side \(debugName): cancel fill")

        if !force {
            guard !hasStarted,
                  !hasLockedInteraction
            else {
                // ignore cancel if we have ongoing auto animation
                print("[Swipe Attestation] side \(debugName): cancel fill - IGNORED")
                return
            }
        }

        let animations = animations
        let currentProgress = progress
        hasLockedInteraction = false
        cancelCurrentAnimator(preservePresentation: false)

        UIView.performWithoutAnimation {
            animations.forEach { $0.view?.transform = $0.finalTransform }
        }

        let animator =
            if let timing {
                UIViewPropertyAnimator(duration: duration, timingParameters: timing)
            } else {
                UIViewPropertyAnimator(duration: duration, curve: .linear)
            }

        animator.addAnimations {
            animations.forEach {
                $0.view?.transform = $0.initialTransform
            }
        }
        animator.addCompletion { [weak self] _ in
            print("[Swipe Attestation] side \(self?.debugName ?? "UNKNOWN"): cancel fill animation completed")
            self?.invertedAnimator = nil
            self?.committedProgress = 0
            self?.completionAction?()
        }
        animator.fractionComplete = 1 - currentProgress

        invertedAnimator = animator
        animator.pauseAnimation()

        animator.continueAnimation(
            withTimingParameters: timing,
            durationFactor: 1
        )

        if force {
            overlayTiming = nil
            hasStarted = false
            invalidateStartTimer()
        }
    }

    // MARK: - Internals

    private func lockIfNearEnd() {
        guard let overlayTiming else {
            return
        }
        print("[Swipe Attestation] side \(debugName): checking overlayTiming \(overlayTiming)")
        let now = CACurrentMediaTime()
        let deadline = overlayTiming.startsAt + overlayTiming.duration
        let desiredRemaining = max(0, deadline - now)
        lockIfNearEnd(remaining: desiredRemaining)
    }

    private func lockIfNearEnd(remaining: TimeInterval) {
        guard !hasLockedInteraction,
              remaining <= Constants.lockInteractionThreshold else {
            return
        }
        print("[Swipe Attestation] side \(debugName): did enter non interruptible phase")
        hasLockedInteraction = true
        delegate?.overlayAnimatorDidEnterNonInterruptiblePhase(self)
    }

    /// If there is no animator, build one from the current presentation → onscreen and keep it paused.
    private func ensureAnimatorReadyForScrub() {
        guard propertyAnimator == nil else {
            print("[Swipe Attestation] side \(debugName): using existing animator")
            propertyAnimator?.pauseAnimation()
            return
        }
        print("[Swipe Attestation] side \(debugName): Creating new animator")

        rebuildAnimator()

        // make animator active but paused
        //        propertyAnimator?.startAnimation()
        propertyAnimator?.pauseAnimation()
    }

    private func rebuildAnimator() {
        let duration = propertyAnimator?.duration ??
            overlayTiming?.duration ??
            Constants.defaultDuration
        let timing = propertyAnimator?.timingParameters

        print("[Swipe Attestation] side \(debugName): Rebuilding animator")
        let views = animations
        let progress = progress

        // stop at current state, preserving current transform state
        propertyAnimator?.pauseAnimation()
        propertyAnimator?.stopAnimation(false)
        propertyAnimator?.finishAnimation(at: .current)

        UIView.performWithoutAnimation {
            animations.forEach { $0.view?.transform = $0.initialTransform }
        }

        let animator =
            if let timing {
                UIViewPropertyAnimator(duration: duration, timingParameters: timing)
            } else {
                UIViewPropertyAnimator(duration: duration, curve: .linear)
            }

        animator.addAnimations {
            views.forEach {
                $0.view?.transform = $0.finalTransform
            }
        }
        animator.addCompletion { [weak self] position in
            guard let self else { return }
            switch position {
            case .end:
                committedProgress = 1
            case .start:
                committedProgress = 0
            case .current:
                committedProgress = propertyAnimator?.fractionComplete ?? committedProgress
            @unknown default:
                break
            }
            print(
                "[Swipe Attestation] side \(debugName): Animator complete with duration \(duration), position \(position)"
            )
            hasLockedInteraction = false
            completionAction?()
        }
        animator.fractionComplete = progress

        propertyAnimator = animator
    }

    /// Start at `startsAt` and finish at the fixed deadline
    private func armStartTimerOrStartNow() {
        guard let timing = overlayTiming else { return }
        let now = CACurrentMediaTime()

        if now >= timing.startsAt {
            print("[Swipe Attestation] side \(debugName) preparing to start auto animation")

            ensureAnimatorReadyForScrub()
            guard let animator = propertyAnimator else { return }

            let deadline = timing.startsAt + timing.duration
            let originalAnimationDuration = animator.duration
            let desiredRemaining = max(0, deadline - now)
            let durationFactor = CGFloat(desiredRemaining / max(originalAnimationDuration, 0.0001))

            if !overlayAnimatorConfigured {
                overlayAnimatorConfigured = true
                let progressLeft = desiredRemaining / timing.duration
                animator.fractionComplete = (1 - progressLeft).clamped(to: 0 ... 1)
            }

            lockIfNearEnd(remaining: desiredRemaining)

            if !hasStarted {
                hasStarted = true
                delegate?.overlayAnimatorDidStartDelayedAnimation(self)
            }
            animator.continueAnimation(
                withTimingParameters: nil,
                durationFactor: max(0, durationFactor)
            )
            animator.addCompletion { [weak self] position in
                guard let self else { return }
                print("[Swipe Attestation] side: \(debugName) Auto animation finished at \(position)")
                if overlayTiming == timing {
                    hasLockedInteraction = false
                    overlayTiming = nil
                    hasStarted = false
                    propertyAnimator = nil
//                    cancelAnimator(animator, preservePresentation: false, inverted: false)
                    delegate?.overlayAnimatorDidFinishAnimation(self)

                    print("[Swipe Attestation] side: \(debugName) Reset auto animation properties")
                }
            }

            invalidateStartTimer()
        } else {
            let interval = max(0, timing.startsAt - now)
            invalidateStartTimer()
            startTimer = Timer.scheduledTimer(
                withTimeInterval: interval,
                repeats: false
            ) { [weak self] _ in
                self?.armStartTimerOrStartNow()
            }
        }
    }

    private func cancelCurrentAnimator(preservePresentation: Bool) {
        if let propertyAnimator {
            cancelAnimator(propertyAnimator, preservePresentation: preservePresentation, inverted: false)
            self.propertyAnimator = nil
            print("[Swipe Attestation] side \(debugName): propertyAnimator cancelled")
        }
        if let invertedAnimator {
            cancelAnimator(invertedAnimator, preservePresentation: preservePresentation, inverted: true)
            self.invertedAnimator = nil
            print("[Swipe Attestation] side \(debugName): invertedAnimator cancelled")
        }
    }

    private func cancelAnimator(
        _ animator: UIViewPropertyAnimator,
        preservePresentation: Bool,
        inverted: Bool
    ) {
        if preservePresentation {
            animator.pauseAnimation()
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
            committedProgress = inverted
                ? 1 - animator.fractionComplete
                : animator.fractionComplete
            hasLockedInteraction = false
        } else {
            animator.stopAnimation(true)
            committedProgress = inverted ? 1 : .zero
            hasLockedInteraction = false
        }
    }

    private func invalidateStartTimer() {
        startTimer?.invalidate()
        startTimer = nil
    }
}
