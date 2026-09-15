import UIKit

protocol OverlayFilterProvider {
    /// Called from the render thread once per frame.
    func sample() -> FilteredMTKRenderer.OverlayFilter?
}

protocol ImageLookProvider {
    func sample() -> FilteredMTKRenderer.ImageLookUniforms?
}

protocol SpatialEffectProvider {
    func sample() -> FilteredMTKRenderer.SpatialEffect?
}

struct FilteredRendererConfiguration {
    let overlayProviders: [OverlayFilterProvider]
    let lookProviders: [ImageLookProvider]
    let spatialEffectProvider: SpatialEffectProvider?
}

extension FilteredRendererConfiguration {
    static var original = FilteredRendererConfiguration(
        overlayProviders: [],
        lookProviders: [],
        spatialEffectProvider: nil
    )
}
