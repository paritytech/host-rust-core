import Foundation
import UIKit

final class AnimatedOverlayProvider: OverlayFilterProvider {
    enum Direction {
        case leftToRight
        case rightToLeft
        case topToBottom
        case bottomToTop
    }

    // Immutable configuration
    let direction: Direction
    let duration: TimeInterval
    let createdAt: CFTimeInterval
    let startsAt: CFTimeInterval?
    let color: SIMD4<Float>
    let corners: SIMD4<Float>

    init(
        startsAt: CFTimeInterval? = nil,
        direction: Direction,
        duration: TimeInterval, // total animation time (seconds)
        color: UIColor, // monotonic start time
        cornerMask: CACornerMask,
        radius: Float = 0 // normalized value [0, 0.5]
    ) {
        self.startsAt = startsAt
        self.direction = direction
        self.duration = max(0, duration)
        self.color = color.simd4()
        corners = cornerMask.cornerSIMD4(radius: radius)
        createdAt = CACurrentMediaTime()
    }

    /// Called from the render thread once per frame.
    func sample() -> FilteredMTKRenderer.OverlayFilter? {
        // Compute elapsed on a monotonic clock.
        let now = CACurrentMediaTime()

        guard now > (startsAt ?? createdAt) else {
            return nil
        }

        let start = startsAt ?? createdAt

        let elapsed = max(0, now - start)

        // Normalized progress 0...1
        let progress = duration > 0 ? min(1, elapsed / duration) : 1

        // If nothing visible yet, skip to save work.
        guard progress > 0 else {
            return nil
        }

        let rect =
            switch direction {
            case .leftToRight:
                CGRect(x: 0, y: 0, width: progress, height: 1)
            case .rightToLeft:
                CGRect(x: 1 - progress, y: 0, width: progress, height: 1)
            case .topToBottom:
                CGRect(x: 0, y: 0, width: 1, height: progress)
            case .bottomToTop:
                CGRect(x: 0, y: 1 - progress, width: 1, height: progress)
            }

        let filter = FilteredMTKRenderer.OverlayFilter(
            rect: rect.simdRect(),
            color: color,
            corners: corners
        )

        return filter
    }
}
