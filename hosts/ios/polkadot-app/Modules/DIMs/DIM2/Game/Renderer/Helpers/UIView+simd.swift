import UIKit

extension UIView {
    /// Per-corner normalized radii for this view's *bounds*.
    /// Normalized by the view's short side in *pixels* (bounds * contentScaleFactor).
    /// Order: (topLeft, topRight, bottomRight, bottomLeft)
    func cornerSIMD4ForBounds() -> SIMD4<Float> {
        let scale = contentScaleFactor
        let scaledWidth = bounds.width * scale
        let scaledHeight = bounds.height * scale
        return cornerSIMD4(
            maskedCorners: layer.maskedCorners,
            cornerRadiusPoints: layer.cornerRadius,
            areaShortSidePixels: max(1, min(scaledWidth, scaledHeight))
        )
    }

    /// Core mapper: converts CALayer.cornerRadius (points) + mask → normalized SIMD4,
    /// corrected for effective horizontal/vertical flips in window coordinates.
    private func cornerSIMD4(
        maskedCorners: CACornerMask,
        cornerRadiusPoints: CGFloat,
        areaShortSidePixels shortSidePx: CGFloat
    ) -> SIMD4<Float> {
        let scaledRadius = max(0, cornerRadiusPoints * contentScaleFactor)
        let normalizedRadius = Float(min(0.5, scaledRadius / max(1, shortSidePx)))

        // Base mapping in the layer's own coordinate space
        var topLeft = maskedCorners.contains(.layerMinXMinYCorner) ? normalizedRadius : 0
        var topRight = maskedCorners.contains(.layerMaxXMinYCorner) ? normalizedRadius : 0
        var bottomRight = maskedCorners.contains(.layerMaxXMaxYCorner) ? normalizedRadius : 0
        var bottomLeft = maskedCorners.contains(.layerMinXMaxYCorner) ? normalizedRadius : 0

        // Correct for effective flips (mirrors) produced by transforms up the hierarchy
        let (isHFlipped, isVFlipped) = effectiveAxisFlips()

        if isHFlipped {
            swap(&topLeft, &topRight)
            swap(&bottomLeft, &bottomRight)
        }
        if isVFlipped {
            swap(&topLeft, &bottomLeft)
            swap(&topRight, &bottomRight)
        }

        return SIMD4<Float>(topLeft, topRight, bottomRight, bottomLeft)
    }

    /// Detect whether the view is effectively mirrored horizontally and/or vertically
    /// in window coordinates (taking superview and layer transforms into account).
    private func effectiveAxisFlips() -> (horizontal: Bool, vertical: Bool) {
        guard let hostLayer = layer.presentation() ?? layer as CALayer?,
              let window = window ?? (self as? UIWindow) else {
            // Fallback: infer from 2D affine transform if we can't convert to window
            // determinant < 0 means a reflection; sign of a/d suggests which axis
            let transform = transform
            let det = transform.a * transform.d - transform.b * transform.c
            let hasMirror = det < 0
            // Heuristic: scaleX < 0 → horizontal flip; scaleY < 0 → vertical flip
            let horizontal = transform.a < 0
            let vertical = transform.d < 0
            return (horizontal: hasMirror && horizontal, vertical: hasMirror && vertical)
        }

        // Use geometric test in window coords
        let pZero = hostLayer.convert(CGPoint(x: 0, y: 0), to: window.layer)
        let pXPoint = hostLayer.convert(CGPoint(x: 1, y: 0), to: window.layer)
        let pYPoint = hostLayer.convert(CGPoint(x: 0, y: 1), to: window.layer)

        let isHFlipped = pXPoint.x < pZero.x
        let isVFlipped = pYPoint.y < pZero.y
        return (isHFlipped, isVFlipped)
    }
}

extension CACornerMask {
    /// Produces (topLeft, topRight, bottomRight, bottomLeft) for a *non-flipped* layer space.
    /// Clamp radius to [0, 0.5].
    func cornerSIMD4(radius: Float) -> SIMD4<Float> {
        let radius = max(0, min(0.5, radius))
        return SIMD4<Float>(
            contains(.layerMinXMinYCorner) ? radius : 0, // top-left
            contains(.layerMaxXMinYCorner) ? radius : 0, // top-right
            contains(.layerMaxXMaxYCorner) ? radius : 0, // bottom-right
            contains(.layerMinXMaxYCorner) ? radius : 0 // bottom-left
        )
    }
}
