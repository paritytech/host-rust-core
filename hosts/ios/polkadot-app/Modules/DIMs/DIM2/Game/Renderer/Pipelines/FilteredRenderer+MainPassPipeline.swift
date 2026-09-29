import Metal
import Foundation

extension FilteredMTKRenderer {
    final class MainPassPipeline {
        private let device: MTLDevice
        private let pipeline: MTLComputePipelineState
        private let threadsPerThreadgroup: MTLSize
        private lazy var fallbackLookBuffer = createFallbackLookBuffer()

        init(
            device: MTLDevice,
            library: MTLLibrary
        ) throws {
            guard let function = library.makeFunction(name: Constants.computeFunctionName) else {
                throw RendererError.missingMetalFunction
            }
            self.device = device
            pipeline = try device.makeComputePipelineState(function: function)
            let width = pipeline.threadExecutionWidth
            let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
            threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)
        }
    }
}

extension FilteredMTKRenderer.MainPassPipeline {
    // swiftlint:disable:next function_parameter_count
    func encode(
        into commandBuffer: MTLCommandBuffer,
        destination: MTLTexture,
        yTexture: MTLTexture,
        uvTexture: MTLTexture?,
        uPlane: MTLTexture?,
        vPlane: MTLTexture?,
        uniforms: FilteredMTKRenderer.FrameUniforms,
        lookBuffer: MTLBuffer?
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "MainPass"
        encoder.setComputePipelineState(pipeline)

        encoder.setTexture(yTexture, index: 0)
        encoder.setTexture(destination, index: 1)
        if let uvTexture { encoder.setTexture(uvTexture, index: 2) }
        if let uPlane { encoder.setTexture(uPlane, index: 3) }
        if let vPlane { encoder.setTexture(vPlane, index: 4) }

        var uniforms = uniforms
        uniforms.outWidth = UInt32(destination.width)
        uniforms.outHeight = UInt32(destination.height)
        uniforms.filterCount = 0 // overlays are not applied here
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<FilteredMTKRenderer.FrameUniforms>.size,
            index: 0
        )

        if let lookBuffer {
            encoder.setBuffer(lookBuffer, offset: 0, index: 1)
        } else if let fallbackLookBuffer {
            encoder.setBuffer(fallbackLookBuffer, offset: 0, index: 1)
        } else {
            return
        }

        let grid = MTLSize(
            width: (destination.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (destination.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }

    private func createFallbackLookBuffer() -> MTLBuffer? {
        let stride = MemoryLayout<FilteredMTKRenderer.ImageLookUniforms>.stride
        let fallbackLookBuffer = device.makeBuffer(
            length: stride,
            options: .storageModeShared
        )
        var value = FilteredMTKRenderer.ImageLookUniforms.defaults
        fallbackLookBuffer?.contents().copyMemory(from: &value, byteCount: stride)
        return fallbackLookBuffer
    }
}
