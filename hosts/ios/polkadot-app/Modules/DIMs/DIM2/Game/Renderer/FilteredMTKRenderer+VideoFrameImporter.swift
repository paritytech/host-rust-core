import CoreVideo
import Metal
import WebRTC

extension FilteredMTKRenderer {
    /// Imports WebRTC frames (NV12 or I420) into Metal textures and derives YUV metadata.
    /// Also exposes a utility to convert WebRTC rotation to "quarter-turn CCW" steps for the shader.
    final class VideoFrameImporter {
        // MARK: - Types

        struct ImportedPlanes {
            enum MatrixType: UInt32 {
                case bt601 = 0
                case bt709
                case smpte240M
                case bt2020NCL
            }

            enum ColorRange: UInt32 {
                case video = 0
                case full
            }

            enum ChromaLayout: UInt32 {
                case nv12 = 0
                case i420
            }

            let yTexture: MTLTexture
            let uvTexture: MTLTexture? // NV12 interleaved (rg8)
            let uTexture: MTLTexture? // I420 U plane (r8)
            let vTexture: MTLTexture? // I420 V plane (r8)
            let matrixType: MatrixType
            let colorRange: ColorRange
            let chromaLayout: ChromaLayout
            let yRef: CVMetalTexture? // keep CVMetalTexture alive (zero-copy path)
            let uvRef: CVMetalTexture?
        }

        // MARK: - Private

        private let device: MTLDevice
        private var textureCache: CVMetalTextureCache?

        // Reusable staging textures for I420 fallback uploads.
        private var i420YTexture: MTLTexture?
        private var i420UTexture: MTLTexture?
        private var i420VTexture: MTLTexture?

        // MARK: - Init

        init(device: MTLDevice) {
            self.device = device

            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
            textureCache = cache
        }
    }
}

// MARK: - Public Handlers

extension FilteredMTKRenderer.VideoFrameImporter {
    func flushTextureCache() {
        guard let cache = textureCache else { return }
        CVMetalTextureCacheFlush(cache, 0)
    }

    /// Converts WebRTC rotation to CCW quarter-turn steps expected by the shader.
    func rotationSteps(for rotation: RTCVideoRotation) -> UInt32 {
        let stepsCW = UInt32(rotation.rawValue / 90) % 4
        return (4 - stepsCW) % 4
    }

    /// Imports the frame into Metal textures. Prefers NV12 zero-copy; falls back to I420 uploads.
    func importPlanes(from frame: RTCVideoFrame) -> ImportedPlanes? {
        let width = Int(frame.width)
        let height = Int(frame.height)

        // Fast NV12 zero-copy path via CVMetalTextureCache.
        if let pixelBuffer = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer {
            return makeNV12Planes(from: pixelBuffer)
        }

        // I420 fallback: upload planes into reusable staging textures.
        if let i420 = frame.buffer as? RTCI420Buffer {
            return makeI420Planes(from: i420, width: width, height: height)
        }

        return nil
    }
}

// MARK: - Private Handlers

extension FilteredMTKRenderer.VideoFrameImporter {
    // MARK: NV12 path (zero-copy)

    private func makeNV12Planes(from pixelBuffer: CVPixelBuffer) -> ImportedPlanes? {
        guard let cache = textureCache else { return nil }

        guard CVPixelBufferIsPlanar(pixelBuffer),
              CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return nil
        }

        let yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)

        var yRef: CVMetalTexture?
        var uvRef: CVMetalTexture?

        func createY() -> OSStatus {
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                cache,
                pixelBuffer,
                nil,
                .r8Unorm,
                yWidth,
                yHeight,
                0,
                &yRef
            )
        }
        func createUV() -> OSStatus {
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                cache,
                pixelBuffer,
                nil,
                .rg8Unorm,
                uvWidth,
                uvHeight,
                1,
                &uvRef
            )
        }

        var yStatus = createY()
        if yStatus != kCVReturnSuccess {
            CVMetalTextureCacheFlush(cache, 0)
            yRef = nil
            yStatus = createY()
        }
        var uvStatus = createUV()
        if uvStatus != kCVReturnSuccess {
            CVMetalTextureCacheFlush(cache, 0)
            uvRef = nil
            uvStatus = createUV()
        }

        guard yStatus == kCVReturnSuccess,
              let yRefUnwrapped = yRef,
              let yTexture = CVMetalTextureGetTexture(yRefUnwrapped),
              uvStatus == kCVReturnSuccess,
              let uvRefUnwrapped = uvRef,
              let uvTexture = CVMetalTextureGetTexture(uvRefUnwrapped)
        else { return nil }

        return ImportedPlanes(
            yTexture: yTexture,
            uvTexture: uvTexture,
            uTexture: nil,
            vTexture: nil,
            matrixType: yuvMatrixType(for: pixelBuffer),
            colorRange: yuvColorRange(for: pixelBuffer),
            chromaLayout: .nv12,
            yRef: yRefUnwrapped,
            uvRef: uvRefUnwrapped
        )
    }

    // MARK: I420 path (uploads)

    private func makeI420Planes(from i420: RTCI420Buffer, width: Int, height: Int) -> ImportedPlanes? {
        // Y plane (full resolution)
        if i420YTexture == nil || i420YTexture!.width != width || i420YTexture!.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            i420YTexture = device.makeTexture(descriptor: descriptor)
            i420YTexture?.label = "I420.Y"
        }

        guard let yTex = i420YTexture else { return nil }

        yTex.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: i420.dataY,
            bytesPerRow: Int(i420.strideY)
        )

        // U/V planes (half resolution)
        let uvWidth = width / 2
        let uvHeight = height / 2

        if i420UTexture == nil || i420UTexture!.width != uvWidth || i420UTexture!.height != uvHeight {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: uvWidth,
                height: uvHeight,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            i420UTexture = device.makeTexture(descriptor: descriptor)
            i420UTexture?.label = "I420.U"
        }

        if i420VTexture == nil || i420VTexture!.width != uvWidth || i420VTexture!.height != uvHeight {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: uvWidth,
                height: uvHeight,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            i420VTexture = device.makeTexture(descriptor: descriptor)
            i420VTexture?.label = "I420.V"
        }

        guard let uTex = i420UTexture, let vTex = i420VTexture else { return nil }

        uTex.replace(
            region: MTLRegionMake2D(0, 0, uvWidth, uvHeight),
            mipmapLevel: 0,
            withBytes: i420.dataU,
            bytesPerRow: Int(i420.strideU)
        )
        vTex.replace(
            region: MTLRegionMake2D(0, 0, uvWidth, uvHeight),
            mipmapLevel: 0,
            withBytes: i420.dataV,
            bytesPerRow: Int(i420.strideV)
        )

        return ImportedPlanes(
            yTexture: yTex,
            uvTexture: nil,
            uTexture: uTex,
            vTexture: vTex,
            matrixType: .bt601,
            colorRange: .full,
            chromaLayout: .i420,
            yRef: nil,
            uvRef: nil
        )
    }

    // MARK: YUV metadata helpers

    private func yuvColorRange(for pixelBuffer: CVPixelBuffer) -> ImportedPlanes.ColorRange {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8PlanarFullRange:
            .full
        default:
            .video
        }
    }

    private func yuvMatrixType(for pixelBuffer: CVPixelBuffer) -> ImportedPlanes.MatrixType {
        guard
            let attachments = CVBufferCopyAttachments(pixelBuffer, .shouldPropagate) as? [CFString: Any],
            let matrixString = attachments[kCVImageBufferYCbCrMatrixKey] as? String
        else {
            return .bt601
        }

        let cfString = matrixString as CFString

        if CFEqual(cfString, kCVImageBufferYCbCrMatrix_ITU_R_709_2) {
            return .bt709
        }
        if CFEqual(cfString, kCVImageBufferYCbCrMatrix_SMPTE_240M_1995) {
            return .smpte240M
        }

        if CFEqual(cfString, kCVImageBufferYCbCrMatrix_ITU_R_2020) {
            return .bt2020NCL
        }

        return .bt601
    }
}
