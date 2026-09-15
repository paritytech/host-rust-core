import Foundation
import UIKit

/// Drives `progress` back and forth within a range using a sine oscillator.
/// Default range is 0…0.5 (collapsed ... middle).
final class BounceProgressDriver: ProgressDriver {
    // MARK: Internals

    private let scheduler: FrameScheduler
    private var phaseRadians: CGFloat = 0

    // MARK: Properties

    weak var target: ProgressRenderable?

    /// progress range to bounce within
    var progressRange: ClosedRange<CGFloat> = 0.0 ... 1 {
        didSet { progressRange = normalized(range: progressRange) }
    }

    /// frequency in Hertz.
    var frequencyHertz: CGFloat = 1 / 2

    var isRunning: Bool { scheduler.isRunning }

    // MARK: Init

    init(
        target: ProgressRenderable? = nil,
        scheduler: FrameScheduler = DisplayLinkFrameScheduler()
    ) {
        self.target = target
        self.scheduler = scheduler
    }

    deinit {
        stop()
    }

    // MARK: - ProgressDriver

    func start(direction: AnimationDirection) {
        guard !scheduler.isRunning else { return }
        seedPhaseFromCurrentProgress(direction: direction)
        scheduler.start { [weak self] timestamp, targetTimestamp in
            guard let self else { return }
            tick(timestamp: timestamp, targetTimestamp: targetTimestamp)
        }
    }

    func stop() {
        scheduler.stop()
    }

    // MARK: - Ticking

    private func tick(timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval) {
        guard let target else { return }
        // Compute delta using target timestamp for improved stability.
        let delta = CGFloat(targetTimestamp - timestamp)
        phaseRadians += 2 * .pi * frequencyHertz * delta
        phaseRadians.formTruncatingRemainder(dividingBy: 2 * .pi)

        let center = (progressRange.lowerBound + progressRange.upperBound) / 2
        let amplitude = (progressRange.upperBound - progressRange.lowerBound) / 2

        let value = center + amplitude * sin(phaseRadians)

        if Thread.isMainThread {
            target.progress = value
        } else {
            DispatchQueue.main.async {
                target.progress = value
            }
        }
    }

    // MARK: Helpers

    private func seedPhaseFromCurrentProgress(direction: AnimationDirection) {
        guard let target else { return }
        let center = (progressRange.lowerBound + progressRange.upperBound) / 2
        let amplitude = max((progressRange.upperBound - progressRange.lowerBound) / 2, .ulpOfOne)
        let normalized = ((target.progress - center) / amplitude).clamped(to: -1 ... 1)
        let base = asin(normalized)
        switch direction {
        case .forward:
            phaseRadians = base
        case .backward:
            phaseRadians = .pi - base
        }
    }

    private func normalized(range: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        let lower = min(max(range.lowerBound, 0), 1)
        let upper = min(max(range.upperBound, 0), 1)
        return min(lower, upper) ... max(lower, upper)
    }
}
