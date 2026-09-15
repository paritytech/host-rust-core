import Foundation

struct PlayerAttestedFilterProvider: ImageLookProvider {
    func sample() -> FilteredMTKRenderer.ImageLookUniforms? {
        .init(
            saturation: 1.20,
            contrast: 1.08,
            shadows: 0.18,
            highlights: 0.22,
            vibrance: 0.25,
            gamma: 1.05,
            temperature: 0.18,
            tint: 0.05,
            splitToneShadows: SIMD3<Float>(0.05, 0.07, 0.15),
            splitToneHighlights: SIMD3<Float>(0.20, 0.12, 0.08),
            balance: 0.25
        )
    }
}
