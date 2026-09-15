import AVFoundation
import Kingfisher
import UIKit
@preconcurrency import SDKLogger

final class IPFSVideoThumbnailProvider: ImageDataProvider {
    let cacheKey: String

    private let asset: AVURLAsset
    private let targetSize: CGSize
    private let logger: LoggerProtocol

    init(
        asset: AVURLAsset,
        identifier: String,
        targetSize: CGSize,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.asset = asset
        self.targetSize = targetSize
        self.logger = logger
        cacheKey = "\(identifier)-\(Int(targetSize.width))x\(Int(targetSize.height))"
    }

    func data(handler: @escaping (Result<Data, Error>) -> Void) {
        Task(priority: .medium) {
            do {
                let imageData = try await generateThumbnail()
                handler(.success(imageData))
            } catch {
                logger.error("Failed to generate IPFS video thumbnail: \(error)")
                handler(.failure(error))
            }
        }
    }

    private func generateThumbnail() async throws -> Data {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = targetSize

        let (cgImage, _) = try await generator.image(at: CMTime(value: 0, timescale: 1))

        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85) else {
            throw IPFSVideoThumbnailError.failedToEncodeImage
        }

        return data
    }
}

enum IPFSVideoThumbnailError: Error {
    case failedToEncodeImage
}
