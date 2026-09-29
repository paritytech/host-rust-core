import Metal
import Foundation

extension FilteredMTKRenderer {
    /// Separable Gaussian blur with optional downsample/upsample.
    /// Encodes: downsample -> blurH -> blurV -> upsample into `destination`.
    final class GaussianPipeline {
        private let downsamplePipeline: MTLComputePipelineState
        private let horizontalBlurPipeline: MTLComputePipelineState
        private let verticalBlurPipeline: MTLComputePipelineState
        private let upsamplePipeline: MTLComputePipelineState

        private let downsampleThreads: MTLSize
        private let horizontalThreads: MTLSize
        private let verticalThreads: MTLSize
        private let upsampleThreads: MTLSize

        init(
            device: MTLDevice,
            library: MTLLibrary
        ) throws {
            func makePipeline(named name: String) throws -> (MTLComputePipelineState, MTLSize) {
                guard let function = library.makeFunction(name: name) else {
                    throw RendererError.missingMetalFunction
                }
                let pipeline = try device.makeComputePipelineState(function: function)
                let width = pipeline.threadExecutionWidth
                let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
                return (pipeline, MTLSize(width: width, height: height, depth: 1))
            }

            (downsamplePipeline, downsampleThreads) = try makePipeline(named: Constants.downsampleFunctionName)
            (horizontalBlurPipeline, horizontalThreads) = try makePipeline(named: Constants.blurHFunctionName)
            (verticalBlurPipeline, verticalThreads) = try makePipeline(named: Constants.blurVFunctionName)
            (upsamplePipeline, upsampleThreads) = try makePipeline(named: Constants.upsampleFunctionName)
        }
    }
}

extension FilteredMTKRenderer.GaussianPipeline {
    /// Applies Gaussian blur to `source` and writes the result into `destination`.
    /// - Parameters:
    ///   - commandBuffer: The command buffer to encode into.
    ///   - source: Full‑resolution input texture.
    ///   - destination: Full‑resolution output texture.
    ///   - device: Metal device (used to allocate intermediates).
    ///   - radius: Blur kernel radius (pixels on the downsampled texture).
    ///   - downsampleFactor: 1 = full‑res, 2 = half, etc.
    func encode(
        into commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        device: MTLDevice,
        radius: UInt32,
        downsampleFactor: UInt32
    ) {
        let factor = max(1, Int(downsampleFactor))
        let lowWidth = max(1, source.width / factor)
        let lowHeight = max(1, source.height / factor)

        let smallDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: lowWidth,
            height: lowHeight,
            mipmapped: false
        )
        smallDesc.usage = [.shaderRead, .shaderWrite]
        smallDesc.storageMode = .private

        guard let smallA = device.makeTexture(descriptor: smallDesc),
              let smallB = device.makeTexture(descriptor: smallDesc) else {
            return
        }
        smallA.label = "Gaussian.smallA"
        smallB.label = "Gaussian.smallB"

        // Downsample: source -> smallA
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "Gaussian.Downsample"
            encoder.setComputePipelineState(downsamplePipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(smallA, index: 1)
            var factor = UInt32(factor)
            encoder.setBytes(&factor, length: MemoryLayout<UInt32>.size, index: 0)

            let grid = MTLSize(
                width: (lowWidth + downsampleThreads.width - 1) / downsampleThreads.width,
                height: (lowHeight + downsampleThreads.height - 1) / downsampleThreads.height,
                depth: 1
            )
            encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: downsampleThreads)
            encoder.endEncoding()
        }

        var radius = radius

        // Horizontal blur: smallA -> smallB
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "Gaussian.Horizontal"
            encoder.setComputePipelineState(horizontalBlurPipeline)
            encoder.setTexture(smallA, index: 0)
            encoder.setTexture(smallB, index: 1)
            encoder.setBytes(&radius, length: MemoryLayout<UInt32>.size, index: 0)

            let grid = MTLSize(
                width: (lowWidth + horizontalThreads.width - 1) / horizontalThreads.width,
                height: (lowHeight + horizontalThreads.height - 1) / horizontalThreads.height,
                depth: 1
            )
            encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: horizontalThreads)
            encoder.endEncoding()
        }

        // Vertical blur: smallB -> smallA
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "Gaussian.Vertical"
            encoder.setComputePipelineState(verticalBlurPipeline)
            encoder.setTexture(smallB, index: 0)
            encoder.setTexture(smallA, index: 1)
            encoder.setBytes(&radius, length: MemoryLayout<UInt32>.size, index: 0)

            let grid = MTLSize(
                width: (lowWidth + verticalThreads.width - 1) / verticalThreads.width,
                height: (lowHeight + verticalThreads.height - 1) / verticalThreads.height,
                depth: 1
            )
            encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: verticalThreads)
            encoder.endEncoding()
        }

        // Upsample: smallA -> destination
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "Gaussian.Upsample"
            encoder.setComputePipelineState(upsamplePipeline)
            encoder.setTexture(smallA, index: 0)
            encoder.setTexture(destination, index: 1)
            var factor = UInt32(factor)
            encoder.setBytes(&factor, length: MemoryLayout<UInt32>.size, index: 0)

            let grid = MTLSize(
                width: (destination.width + upsampleThreads.width - 1) / upsampleThreads.width,
                height: (destination.height + upsampleThreads.height - 1) / upsampleThreads.height,
                depth: 1
            )
            encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: upsampleThreads)
            encoder.endEncoding()
        }
    }
}
