import Foundation
import CoreImage
import UIKit
@preconcurrency import WebRTC

final class RTCVideoCapturerWrapper {
    private let videoCapturer: RTCVideoCapturer
    private let videoProfile: RTCVideoProfile

    private var isStarted = false

    init(videoSource: RTCVideoSource, videoProfile: RTCVideoProfile) {
        self.videoProfile = videoProfile

        #if targetEnvironment(simulator)
            videoCapturer = SimulatedVideoCapturer(delegate: videoSource)
        #else
            videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        #endif
    }

    func start() {
        guard !isStarted else { return }

        if performStart() {
            isStarted = true
        }
    }

    func stop() {
        guard isStarted else { return }

        performStop()
        isStarted = false
    }
}

private extension RTCVideoCapturerWrapper {
    func performStart() -> Bool {
        #if targetEnvironment(simulator)
            guard let videoCapturer = videoCapturer as? SimulatedVideoCapturer else {
                return false
            }

            videoCapturer.startCapture()
            return true
        #else
            guard let videoCapturer = videoCapturer as? RTCCameraVideoCapturer else {
                return false
            }

            let captureStrategy = VideoCaptureStrategy(preferences: .init(profile: videoProfile))
            guard
                let frontCamera = RTCCameraVideoCapturer
                .captureDevices()
                .first(where: { $0.position == .front }),
                let params = captureStrategy.deriveParams(for: frontCamera)
            else {
                return false
            }

            videoCapturer.startCapture(
                with: frontCamera,
                format: params.format,
                fps: params.fps
            )
            return true
        #endif
    }

    func performStop() {
        #if targetEnvironment(simulator)
            (videoCapturer as? SimulatedVideoCapturer)?.stopCapture()
        #else
            (videoCapturer as? RTCCameraVideoCapturer)?.stopCapture()
        #endif
    }
}

#if targetEnvironment(simulator)
    private final class SimulatedVideoCapturer: RTCVideoCapturer {
        private let timerQueue = DispatchQueue(label: "SimulatedVideoCapturer")
        private var timer: DispatchSourceTimer?
        private var frameIndex = 0
        private let ciContext = CIContext()
        private let width: CGFloat = 480
        private let height: CGFloat = 640

        override init(delegate: RTCVideoCapturerDelegate) {
            super.init(delegate: delegate)
        }

        func startCapture(fps: Int = 30) {
            stopCapture()

            let timer = DispatchSource.makeTimerSource(queue: timerQueue)
            timer.schedule(deadline: .now(), repeating: 1.0 / Double(fps))
            timer.setEventHandler { [weak self] in
                self?.sendFrame()
            }
            timer.resume()
            self.timer = timer
        }

        func stopCapture() {
            timer?.cancel()
            timer = nil
        }

        private func sendFrame() {
            frameIndex += 1

            var image: UIImage?
            DispatchQueue.main.sync {
                image = generateImage(frameIndex: frameIndex)
            }

            guard let image, let nv12Buffer = createNV12Buffer(from: image) else { return }

            let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: nv12Buffer)
            let timeStampNs = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
            let frame = RTCVideoFrame(buffer: rtcBuffer, rotation: ._0, timeStampNs: timeStampNs)

            delegate?.capturer(self, didCapture: frame)
        }

        private func generateImage(frameIndex: Int) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1

            return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
                UIColor.darkGray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

                UIColor.systemTeal.setFill()

                let xOffset = sin(Double(frameIndex) * 0.1) * 50.0
                let circleBaseX = (width - 300) / 2
                let circleX = circleBaseX + xOffset
                let circleY = (height - 300) / 2

                ctx.cgContext.fillEllipse(in: CGRect(x: circleX, y: circleY, width: 300, height: 300))

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let string = "SIMULATOR"
                let size = string.size(withAttributes: attrs)

                let textX = circleX + (300 - size.width) / 2.0
                let textY = circleY + (300 - size.height) / 2.0

                string.draw(
                    at: CGPoint(x: textX, y: textY),
                    withAttributes: attrs
                )
            }
        }

        private func createNV12Buffer(from image: UIImage) -> CVPixelBuffer? {
            guard let cgImage = image.cgImage else { return nil }

            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferWidthKey as String: Int(width),
                kCVPixelBufferHeightKey as String: Int(height)
            ]

            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(width),
                Int(height),
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                attributes as CFDictionary,
                &buffer
            )

            guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }

            let ciImage = CIImage(cgImage: cgImage)
            ciContext.render(ciImage, to: pixelBuffer)

            return pixelBuffer
        }
    }
#endif
