import Metal
import Foundation

extension FilteredMTKRenderer {
    /// Final pass: copies `source` to `destination` and composites color overlays.
    final class OverlaysPipeline {
        private let pipeline: MTLComputePipelineState
        private let threadsPerThreadgroup: MTLSize

        init(
            device: MTLDevice,
            library: MTLLibrary
        ) throws {
            guard let function = library.makeFunction(name: Constants.overlaysFunctionName) else {
                throw RendererError.missingMetalFunction
            }
            pipeline = try device.makeComputePipelineState(function: function)
            let width = pipeline.threadExecutionWidth
            let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
            threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)
        }
    }
}

extension FilteredMTKRenderer.OverlaysPipeline {
    /// Applies overlays and writes to `destination`. If `filtersBuffer` is nil,
    /// a CPU fallback array is uploaded instead.
    func encode(
        into commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        uniforms: FilteredMTKRenderer.FrameUniforms,
        filtersBuffer: MTLBuffer?,
        cpuFallback: [FilteredMTKRenderer.OverlayFilter]
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Overlays"
        encoder.setComputePipelineState(pipeline)

        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)

        var uniforms = uniforms
        uniforms.outWidth = UInt32(destination.width)
        uniforms.outHeight = UInt32(destination.height)
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<FilteredMTKRenderer.FrameUniforms>.size,
            index: 0
        )

        if let filtersBuffer {
            encoder.setBuffer(filtersBuffer, offset: 0, index: 1)
        } else if !cpuFallback.isEmpty {
            var tmp = cpuFallback
            encoder.setBytes(
                &tmp,
                length: MemoryLayout<FilteredMTKRenderer.OverlayFilter>.stride * tmp.count,
                index: 1
            )
        }

        let grid = MTLSize(
            width: (destination.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (destination.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }
}
