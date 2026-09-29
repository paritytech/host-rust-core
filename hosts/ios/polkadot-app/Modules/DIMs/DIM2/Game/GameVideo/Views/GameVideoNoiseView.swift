import MetalKit

final class GameVideoNoiseView: MTKView {
    private struct Uniforms {
        var resolution: SIMD2<Float>
        var intensity: Float
        var frame: UInt32
        var gridCells: UInt32
    }

    private enum Constants {
        static let gridCells: UInt32 = 160
        static let defaultMaxLuma: Double = 85
    }

    private var clampedIntensity: Double = Constants.defaultMaxLuma / 255.0
    var intensity: Double {
        get { clampedIntensity }
        set { clampedIntensity = min(max(newValue, 0), 1) }
    }

    private var clampedSpeed: Double = 0.6
    var speed: Double {
        get { clampedSpeed }
        set {
            clampedSpeed = min(max(newValue, 0), 1)
            preferredFramesPerSecond = Self.framesPerSecond(for: clampedSpeed)
        }
    }

    private let renderCommandQueue: MTLCommandQueue?
    private var frameCounter: UInt32 = 0

    private static var sharedPipeline: MTLRenderPipelineState?

    init() {
        let metalDevice = MTLCreateSystemDefaultDevice()
        renderCommandQueue = metalDevice?.makeCommandQueue()
        super.init(frame: .zero, device: metalDevice)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isOpaque = true
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .black
        enableSetNeedsDisplay = false
        isPaused = true
        preferredFramesPerSecond = Self.framesPerSecond(for: speed)
        delegate = self

        if let metalDevice {
            Self.buildPipelineIfNeeded(device: metalDevice, pixelFormat: colorPixelFormat)
        }
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startAnimating() {
        isPaused = false
    }

    func stopAnimating() {
        isPaused = true
    }
}

// MARK: - Private functions

extension GameVideoNoiseView {
    private static func framesPerSecond(for speed: Double) -> Int {
        Int((5.0 + speed * 25.0).rounded())
    }

    private static func buildPipelineIfNeeded(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        guard sharedPipeline == nil else { return }
        let library = device.makeDefaultLibrary()
        guard
            let vertexFunction = library?.makeFunction(name: "noise_vertex"),
            let fragmentFunction = library?.makeFunction(name: "noise_fragment")
        else {
            return
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        sharedPipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
    }
}

// MARK: - MTKViewDelegate

extension GameVideoNoiseView: MTKViewDelegate {
    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let pipeline = Self.sharedPipeline,
            let drawable = view.currentDrawable,
            let passDescriptor = view.currentRenderPassDescriptor,
            let commandQueue = renderCommandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            return
        }

        frameCounter &+= 1
        var uniforms = Uniforms(
            resolution: SIMD2(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            ),
            intensity: Float(intensity),
            frame: frameCounter,
            gridCells: Constants.gridCells
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
