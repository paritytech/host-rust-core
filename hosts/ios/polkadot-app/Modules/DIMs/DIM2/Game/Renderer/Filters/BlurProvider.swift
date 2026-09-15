import Foundation

struct BlurProvider: SpatialEffectProvider {
    var radius: UInt32 = 3 // 1..7 (odd works best)
    var downsample: UInt32 = 1 // 1=full-res, 2=half, etc.
    func sample() -> FilteredMTKRenderer.SpatialEffect? {
        .gaussian(radius: radius, downsample: downsample)
    }
}
