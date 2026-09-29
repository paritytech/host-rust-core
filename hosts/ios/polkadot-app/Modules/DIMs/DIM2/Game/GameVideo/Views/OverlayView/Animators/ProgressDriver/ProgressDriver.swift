import Foundation

/// A driver that advances a ProgressRenderable over time.
protocol ProgressDriver: AnyObject {
    var target: ProgressRenderable? { get set }
    var isRunning: Bool { get }
    func start(direction: AnimationDirection)
    func stop()
}

extension ProgressDriver {
    func start() {
        start(direction: (target?.isProgressingForward == false) ? .backward : .forward)
    }
}

enum AnimationDirection {
    case forward
    case backward
}
