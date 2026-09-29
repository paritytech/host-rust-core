import CoreVideo
import Foundation
import Metal
import MetalKit
import OSLog
import UIKit
import WebRTC

// MARK: - Renderer

final class FilteredMTKRenderer: NSObject {
    // MARK: Types

    enum RendererError: Error {
        case metalIsNotAvailable
        case failedToLoadDefaultLibrary
        case missingMetalFunction
        case failedToCreateComputePipelineState
    }

    enum RectSpace: UInt32 {
        case sourceUV = 0
        case displayUV = 1
    }

    enum Constants {
        static let inFlightMax = 3
        static let maxFilters = 8
        static let sharedBufferCount = 3
        static let computeFunctionName = "yuvToRgb"
        static let blurHFunctionName = "gaussianBlurHorizontal"
        static let blurVFunctionName = "gaussianBlurVertical"
        static let overlaysFunctionName = "compositeOverlays"
        static let downsampleFunctionName = "downsampleBoxAverage"
        static let upsampleFunctionName = "upsampleBilinear"
    }

    // Reuse one CIContext to avoid per-call setup costs.
    private static let previewCIContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: Public API

    /// Rects attach to what you see on screen regardless of camera rotation (default).
    var rectSpace: RectSpace = .displayUV

    private(set) var view: MTKView

    // MARK: Metal

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private let frameImporter: VideoFrameImporter

    private var mainPassPipeline: MainPassPipeline
    private var gaussianPipeline: GaussianPipeline
    private var overlaysPipeline: OverlaysPipeline

    // Cap in flight frames.
    private let inFlightSemaphore = DispatchSemaphore(value: Constants.inFlightMax)

    // Shared state between WebRTC and render threads.
    private let lock = NSLock()

    // Pending (written by WebRTC thread in renderFrame)
    private var pendingYTexture: MTLTexture?
    private var pendingUVTexture: MTLTexture?
    private var pendingUPlane: MTLTexture?
    private var pendingVPlane: MTLTexture?
    private var pendingYCVRef: CVMetalTexture?
    private var pendingUVCVRef: CVMetalTexture?
    private var pendingUniforms = FrameUniforms.empty()
    private var hasNewFrame = false

    // Current (persist across draws)
    private var currentYTexture: MTLTexture?
    private var currentUVTexture: MTLTexture?
    private var currentUPlane: MTLTexture?
    private var currentVPlane: MTLTexture?
    private var currentYCVRef: CVMetalTexture?
    private var currentUVCVRef: CVMetalTexture?
    private var currentUniforms = FrameUniforms.empty()

    // Providers (CPU-side staging)
    private var overlayProviders: [OverlayFilterProvider] = []
    private var imageLookProviders: [ImageLookProvider] = []
    private var spatialEffectProvider: SpatialEffectProvider?

    // Triple buffered shared memory for Filters
    private var filterBuffers: [MTLBuffer] = []

    // Triple buffered shared memory for Looks
    private var lookBuffers: [MTLBuffer] = []

    private var frameIndex: UInt64 = 0

    private var workTexture: MTLTexture?

    // MARK: Init

    init(frameRate: Int = 30) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw RendererError.metalIsNotAvailable
        }
        self.device = device
        self.commandQueue = commandQueue

        let library = try Self.makeLibrary(device: device)

        mainPassPipeline = try MainPassPipeline(device: device, library: library)
        overlaysPipeline = try OverlaysPipeline(device: device, library: library)
        gaussianPipeline = try GaussianPipeline(device: device, library: library)

        view = Self.createView(device: device, preferredFramesPerSecond: frameRate)

        frameImporter = VideoFrameImporter(device: device)

        super.init()

        view.delegate = self

        filterBuffers = makeFilterRingBuffers(
            device: device,
            capacity: Constants.maxFilters,
            count: Constants.sharedBufferCount
        )

        lookBuffers = makeLookRingBuffers(
            device: device,
            capacity: 1, // All looks are computed into single look
            count: Constants.sharedBufferCount
        )

        observeMemoryState()
    }

    // MARK: Public API

    func updateProviders(
        overlays overlayProviders: [OverlayFilterProvider],
        looks imageLookProviders: [ImageLookProvider],
        spatial spatialEffectProvider: SpatialEffectProvider?
    ) {
        lock.lock()
        self.overlayProviders = overlayProviders
        self.imageLookProviders = imageLookProviders
        self.spatialEffectProvider = spatialEffectProvider
        lock.unlock()
    }

    /// Renders the current video frame to an offscreen texture with **no overlays**
    /// and returns a UIImage. Matches the view’s current rotation and sizing.
    func makeUnfilteredPreviewImage(scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        // Snapshot current textures & uniforms under the lock.
        lock.lock()
        let yTexture = currentYTexture
        let uvTexture = currentUVTexture
        let uPlane = currentUPlane
        let vPlane = currentVPlane
        var uniforms = currentUniforms
        lock.unlock()

        guard let yTexture else { return nil }

        // Choose output size to match what the view would draw.
        let outWidth = max(1, Int(view.drawableSize.width.rounded()))
        let outHeight = max(1, Int(view.drawableSize.height.rounded()))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: view.colorPixelFormat,
            width: outWidth,
            height: outHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]
        guard let outTexture = device.makeTexture(descriptor: descriptor) else { return nil }
        outTexture.label = "UnfilteredPreview.out"

        uniforms.outWidth = UInt32(outWidth)
        uniforms.outHeight = UInt32(outHeight)
        uniforms.filterCount = 0

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }

        // Use the main pass pipeline instead of manual encoder setup.
        mainPassPipeline.encode(
            into: commandBuffer,
            destination: outTexture,
            yTexture: yTexture,
            uvTexture: uvTexture,
            uPlane: uPlane,
            vPlane: vPlane,
            uniforms: uniforms,
            lookBuffer: nil
        )

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Convert MTLTexture -> UIImage via CI (GPU path).
        guard let ciImage = CIImage(
            mtlTexture: outTexture,
            options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]
        ) else {
            return nil
        }

        let flip = CGAffineTransform(
            translationX: 0,
            y: CGFloat(outHeight)
        ).scaledBy(x: 1, y: -1)

        let flippedImage = ciImage.transformed(by: flip)

        let rect = CGRect(x: 0, y: 0, width: outWidth, height: outHeight)
        guard let cgImage = Self.previewCIContext.createCGImage(flippedImage, from: rect) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}

// MARK: RTCVideoRenderer

extension FilteredMTKRenderer: RTCVideoRenderer {
    func setSize(_ size: CGSize) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let texAR = size.width / size.height
            let viewPts = view.bounds.size
            let viewAR = viewPts.width / viewPts.height

            var targetPts: CGSize
            if viewAR > texAR {
                // limited by height
                let height = viewPts.height
                let width = height * texAR
                targetPts = CGSize(width: width, height: height)
            } else {
                // limited by width
                let width = viewPts.width
                let height = width / texAR
                targetPts = CGSize(width: width, height: height)
            }

            // convert to pixels
            let screenScale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale

            view.drawableSize = CGSize(
                width: targetPts.width * screenScale,
                height: targetPts.height * screenScale
            )
        }
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        guard let planes = frameImporter.importPlanes(from: frame) else { return }

        let rotationSteps = frameImporter.rotationSteps(for: frame.rotation)

        lock.lock()
        pendingYTexture = planes.yTexture
        pendingUVTexture = planes.uvTexture
        pendingUPlane = planes.uTexture
        pendingVPlane = planes.vTexture
        pendingYCVRef = planes.yRef
        pendingUVCVRef = planes.uvRef

        pendingUniforms = FrameUniforms(
            srcWidth: UInt32(frame.width),
            srcHeight: UInt32(frame.height),
            outWidth: 0,
            outHeight: 0,
            rotationSteps: rotationSteps,
            rectSpace: rectSpace.rawValue,
            filterCount: UInt32(min(overlayProviders.count, Constants.maxFilters)),
            matrixType: planes.matrixType.rawValue,
            fullRange: planes.colorRange.rawValue,
            chromaLayout: planes.chromaLayout.rawValue
        )
        hasNewFrame = true
        lock.unlock()
    }
}

// MARK: MTKViewDelegate

extension FilteredMTKRenderer: MTKViewDelegate {
    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        // 1) Swap in pending frame and snapshot shared state under the lock.
        let snapshot = swapAndSnapshotUnderLock()

        // Nothing to draw without a source.
        guard let yTexture = snapshot.yTexture else { return }

        // 2) Build the per-frame look (outside the lock).
        var look = ImageLookUniforms.defaults
        updateLook(look: &look, with: snapshot.lookProviders)

        let spatialEffectSample = snapshot.spatialProvider?.sample()

        // 3) Gate in-flight work and pick the ring slot AFTER the wait.
        inFlightSemaphore.wait()
        let ringIndex = Int(frameIndex % UInt64(max(filterBuffers.count, 1)))
        let filterBuffer = filterBuffers[safe: ringIndex]
        let lookBuffer = lookBuffers[safe: ringIndex]

        // Upload look for this frame.
        if let lookBuffer {
            var tmp = look
            lookBuffer.contents().copyMemory(from: &tmp, byteCount: MemoryLayout<ImageLookUniforms>.stride)
        }

        autoreleasepool {
            // 4) Get a drawable and command buffer.
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                inFlightSemaphore.signal()
                return
            }
            commandBuffer.label = "FilteredMTKRenderer_CMD"

            // 5) Ensure the working texture matches the drawable.
            ensureWorkingTexture(
                size: MTLSize(width: drawable.texture.width, height: drawable.texture.height, depth: 1),
                pixelFormat: view.colorPixelFormat
            )
            guard let workTexture else {
                inFlightSemaphore.signal()
                return
            }

            // 6) Main pass (YUV → RGB + inline look) -> intermediate
            mainPassPipeline.encode(
                into: commandBuffer,
                destination: workTexture,
                yTexture: yTexture,
                uvTexture: snapshot.uvTexture,
                uPlane: snapshot.uPlane,
                vPlane: snapshot.vPlane,
                uniforms: snapshot.uniforms,
                lookBuffer: lookBuffer
            )

            // 7) Optional spatial effects (e.g., Gaussian blur)
            if let spatialEffectSample {
                switch spatialEffectSample {
                case let .gaussian(radius, downsample):
                    gaussianPipeline.encode(
                        into: commandBuffer,
                        source: workTexture,
                        destination: workTexture,
                        device: device,
                        radius: radius,
                        downsampleFactor: downsample
                    )
                }
            }

            // 8) Sample overlays and upload to the ring buffer.
            let gpuFilters = snapshot.overlayProviders.compactMap { $0.sample() }
            uploadFilters(gpuFilters, to: filterBuffer)

            // Clamp to actual sampled overlay count.
            var uniforms = snapshot.uniforms
            uniforms.outWidth = UInt32(drawable.texture.width)
            uniforms.outHeight = UInt32(drawable.texture.height)
            uniforms.filterCount = UInt32(min(gpuFilters.count, Int(Constants.maxFilters)))

            // 9) Final overlays -> drawable
            overlaysPipeline.encode(
                into: commandBuffer,
                source: workTexture,
                destination: drawable.texture,
                uniforms: uniforms,
                filtersBuffer: filterBuffer,
                cpuFallback: gpuFilters
            )

            // Keep zero-copy CVMetalTexture refs alive until GPU completes.
            keepCVRefsAlive(yRef: snapshot.yRef, uvRef: snapshot.uvRef, on: commandBuffer)

            commandBuffer.addCompletedHandler { [weak self] _ in
                self?.inFlightSemaphore.signal()
            }

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        frameIndex &+= 1
    }
}

private extension FilteredMTKRenderer {
    // MARK: Helpers (setup)

    static func createView(device: MTLDevice, preferredFramesPerSecond: Int) -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.contentScaleFactor = UIScreen.main.scale
        view.autoResizeDrawable = false
        view.isOpaque = true
        return view
    }

    static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: Bundle(for: Self.self)) {
            return library
        } else if let library = try? device.makeDefaultLibrary(bundle: .main) {
            return library
        } else if let library = device.makeDefaultLibrary() {
            return library
        } else {
            throw RendererError.failedToLoadDefaultLibrary
        }
    }

    func ensureWorkingTexture(size: MTLSize, pixelFormat: MTLPixelFormat) {
        if workTexture?.width != size.width ||
            workTexture?.height != size.height ||
            workTexture?.pixelFormat != pixelFormat {
            workTexture = makeTexture(label: "WorkingTexture", pixelFormat: pixelFormat, size: size)
        }
    }

    func makeTexture(label: String, pixelFormat: MTLPixelFormat, size: MTLSize) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: size.width,
            height: size.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    func makeFilterRingBuffers(device: MTLDevice, capacity: Int, count: Int) -> [MTLBuffer] {
        let bytesPerBuffer = MemoryLayout<OverlayFilter>.stride * capacity
        var buffers: [MTLBuffer] = []
        buffers.reserveCapacity(count)
        for _ in 0 ..< count {
            if let buffer = device.makeBuffer(length: bytesPerBuffer, options: .storageModeShared) {
                buffer.label = "FiltersShared"
                buffers.append(buffer)
            }
        }
        return buffers
    }

    func makeLookRingBuffers(device: MTLDevice, capacity: Int, count: Int) -> [MTLBuffer] {
        let bytesPerBuffer = MemoryLayout<ImageLookUniforms>.stride * capacity
        var buffers: [MTLBuffer] = []
        buffers.reserveCapacity(count)
        for _ in 0 ..< count {
            if let buffer = device.makeBuffer(length: bytesPerBuffer, options: .storageModeShared) {
                buffer.label = "ImageLookUniforms"
                buffers.append(buffer)
            }
        }
        return buffers
    }

    func observeMemoryState() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.frameImporter.flushTextureCache()
        }
    }

    // MARK: - Helpers (Snapshot & inputs)

    struct FrameSnapshot {
        let yTexture: MTLTexture?
        let uvTexture: MTLTexture?
        let uPlane: MTLTexture?
        let vPlane: MTLTexture?
        let yRef: CVMetalTexture?
        let uvRef: CVMetalTexture?
        let uniforms: FrameUniforms
        let overlayProviders: [OverlayFilterProvider]
        let lookProviders: [ImageLookProvider]
        let spatialProvider: SpatialEffectProvider?
    }

    func swapAndSnapshotUnderLock() -> FrameSnapshot {
        lock.lock()
        if hasNewFrame {
            currentYTexture = pendingYTexture
            currentUVTexture = pendingUVTexture
            currentUPlane = pendingUPlane
            currentVPlane = pendingVPlane
            currentYCVRef = pendingYCVRef
            currentUVCVRef = pendingUVCVRef
            currentUniforms = pendingUniforms

            pendingYTexture = nil
            pendingUVTexture = nil
            pendingUPlane = nil
            pendingVPlane = nil
            pendingYCVRef = nil
            pendingUVCVRef = nil
            hasNewFrame = false
        }

        let snapshot = FrameSnapshot(
            yTexture: currentYTexture,
            uvTexture: currentUVTexture,
            uPlane: currentUPlane,
            vPlane: currentVPlane,
            yRef: currentYCVRef,
            uvRef: currentUVCVRef,
            uniforms: currentUniforms,
            overlayProviders: overlayProviders, // just snapshots of arrays
            lookProviders: imageLookProviders,
            spatialProvider: spatialEffectProvider
        )
        lock.unlock()
        return snapshot
    }

    func updateLook(
        look: inout FilteredMTKRenderer.ImageLookUniforms,
        with providers: [any ImageLookProvider]
    ) {
        providers.forEach {
            guard let sample = $0.sample() else { return }
            look.saturation *= sample.saturation
            look.contrast *= sample.contrast
            look.shadows += sample.shadows
            look.highlights += sample.highlights
            look.vibrance += sample.vibrance
            look.gamma *= sample.gamma
            look.temperature += sample.temperature
            look.tint += sample.tint
            look.splitToneShadows += sample.splitToneShadows
            look.splitToneHighlights += sample.splitToneHighlights
            look.balance += sample.balance
        }
    }

    func keepCVRefsAlive(
        yRef: CVMetalTexture?,
        uvRef: CVMetalTexture?,
        on commandBuffer: MTLCommandBuffer
    ) {
        guard yRef != nil || uvRef != nil else { return }
        commandBuffer.addCompletedHandler { _ in
            // Capture and touch to extend lifetime until GPU is done
            _ = yRef
            _ = uvRef
        }
    }

    // MARK: Helpers (render loop)

    func uploadFilters(_ filters: [OverlayFilter], to buffer: MTLBuffer?) {
        guard let buffer else { return }
        let count = min(filters.count, Constants.maxFilters)
        guard count > 0 else { return }
        let destination = buffer.contents().bindMemory(to: OverlayFilter.self, capacity: Constants.maxFilters)
        filters.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            destination.update(from: base, count: count)
        }
    }
}

// MARK: - GPU structs (must match Metal shader layouts)

extension FilteredMTKRenderer {
    struct OverlayFilter {
        var rect: SIMD4<Float> // x, y, w, h
        var color: SIMD4<Float> // premultiplied RGBA
        var corners: SIMD4<Float> // radii
    }

    struct FrameUniforms {
        var srcWidth: UInt32
        var srcHeight: UInt32
        var outWidth: UInt32
        var outHeight: UInt32
        var rotationSteps: UInt32
        var rectSpace: UInt32
        var filterCount: UInt32
        var matrixType: UInt32
        var fullRange: UInt32
        /// 0 = NV12 (interleaved RG), 1 = I420 (U & V planes)
        var chromaLayout: UInt32

        static func empty() -> FrameUniforms {
            FrameUniforms(
                srcWidth: 0,
                srcHeight: 0,
                outWidth: 0,
                outHeight: 0,
                rotationSteps: 0,
                rectSpace: FilteredMTKRenderer.RectSpace.displayUV.rawValue,
                filterCount: 0,
                matrixType: 0,
                fullRange: 1,
                chromaLayout: 0
            )
        }
    }

    struct ImageLookUniforms {
        var saturation: Float // global saturation
        var contrast: Float // contrast multiplier
        var shadows: Float // lift darks
        var highlights: Float // compress highlights
        var vibrance: Float // smart sat (protects skin tones)
        var gamma: Float // gamma correction
        var temperature: Float // warm (+) / cool (-)
        var tint: Float // green (-) / magenta (+)
        var splitToneShadows: SIMD3<Float> // color to tint shadows
        var splitToneHighlights: SIMD3<Float> // color to tint highlights
        var balance: Float // blend factor between shadows & highlights

        static var defaults: ImageLookUniforms {
            .init(
                saturation: 1.0,
                contrast: 1.0,
                shadows: 0.0,
                highlights: 0.0,
                vibrance: 0.0,
                gamma: 1.0,
                temperature: 0.0,
                tint: 0.0,
                splitToneShadows: .zero,
                splitToneHighlights: .zero,
                balance: 0.0
            )
        }
    }

    enum SpatialEffect {
        case gaussian(radius: UInt32, downsample: UInt32)
    }
}
