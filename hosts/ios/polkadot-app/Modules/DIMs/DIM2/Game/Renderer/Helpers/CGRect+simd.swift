import Foundation

extension CGRect {
    func simdRect() -> SIMD4<Float> {
        SIMD4<Float>(
            Float(minX),
            Float(minY),
            Float(width),
            Float(height)
        )
    }
}
