import Foundation
import UIKit

// MARK: - Default Frame Scheduler (CADisplayLink)

final class DisplayLinkFrameScheduler: FrameScheduler {
    private(set) var isRunning: Bool = false

    private var displayLink: CADisplayLink?
    private var handler: ((_ timestamp: CFTimeInterval, _ targetTimestamp: CFTimeInterval) -> Void)?

    init() {}

    func start(handler: @escaping (_ timestamp: CFTimeInterval, _ targetTimestamp: CFTimeInterval) -> Void) {
        stop()
        self.handler = handler
        let link = CADisplayLink(target: self, selector: #selector(step))

        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        isRunning = true
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        handler = nil
        isRunning = false
    }

    @objc private func step(_ link: CADisplayLink) {
        handler?(link.timestamp, link.targetTimestamp)
    }
}
