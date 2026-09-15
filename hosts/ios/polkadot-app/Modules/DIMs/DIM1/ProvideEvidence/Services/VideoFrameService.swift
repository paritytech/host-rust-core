import UIKit
import AVFoundation

protocol VideoFrameServicing: AnyObject {
    func getFrame(at second: TimeInterval, from url: URL) throws -> UIImage
}

final class VideoFrameService: VideoFrameServicing {
    func getFrame(at second: TimeInterval, from url: URL) throws -> UIImage {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: second, preferredTimescale: 600)

        let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
        return UIImage(cgImage: cgImage)
    }
}
