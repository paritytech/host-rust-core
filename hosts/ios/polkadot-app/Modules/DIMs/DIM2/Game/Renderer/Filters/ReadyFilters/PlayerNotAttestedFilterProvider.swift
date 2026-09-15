import Foundation
import UIKit

struct PlayerNotAttestedFilterProvider: ImageLookProvider, OverlayFilterProvider, SpatialEffectProvider {
    let overlayFilter: FilteredMTKRenderer.OverlayFilter = {
        let corners: CACornerMask = [.layerMaxXMaxYCorner, .layerMaxXMinYCorner]

        return FilteredMTKRenderer.OverlayFilter(
            rect: SIMD4<Float>(0, 0, 1, 1),
            color: UIColor(red: 0.66, green: 0.48, blue: 0.33, alpha: 0.16).simd4(),
            corners: corners.cornerSIMD4(radius: 0.3)
        )
    }()

    let lookFilter: FilteredMTKRenderer.ImageLookUniforms = {
        var sample = FilteredMTKRenderer.ImageLookUniforms.defaults
        sample.saturation = 0
        return sample
    }()

    let bluer: FilteredMTKRenderer.SpatialEffect = .gaussian(radius: 1, downsample: 4)

    func sample() -> FilteredMTKRenderer.OverlayFilter? {
        overlayFilter
    }

    func sample() -> FilteredMTKRenderer.SpatialEffect? {
        bluer
    }

    func sample() -> FilteredMTKRenderer.ImageLookUniforms? {
        lookFilter
    }
}
