import UIKit

/// Something that can be driven by a normalized progress value (0…1).
protocol ProgressRenderable: AnyObject {
    var progress: CGFloat { get set }

    func animate(to progress: CGFloat, duration: TimeInterval)

    var isProgressingForward: Bool { get }
}

protocol ArrowStateRenderable: UIView, ProgressRenderable {}
