import Kingfisher
import Foundation
import QuickLookThumbnailing
import UIKit
@preconcurrency import SDKLogger

final class EvidenceImageDataProvider: ImageDataProvider {
    let cacheKey: String
    private let mediaType: EvidenceMediaType
    private let url: URL
    private let targetSize: CGSize
    private let logger: LoggerProtocol

    init(
        mediaType: EvidenceMediaType,
        url: URL,
        targetSize: CGSize,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.mediaType = mediaType
        self.url = url
        self.targetSize = targetSize
        self.logger = logger
        cacheKey = "\(url.absoluteString)-\(Int(targetSize.width))x\(Int(targetSize.height))"
    }

    func data(handler: @escaping (Result<Data, Error>) -> Void) {
        Task(priority: .medium) {
            do {
                let imageData = try await generateThumbnail()
                handler(.success(imageData))
            } catch {
                logger.error("Failed to generate evidence thumbnail: \(error)")
                handler(.failure(error))
            }
        }
    }

    private func generateThumbnail() async throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EvidenceImageDataProviderError.fileNotFound
        }

        if mediaType == .photo {
            return try Data(contentsOf: url)
        }

        let scale = await MainActor.run { UIScreen.main.scale }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: targetSize,
            scale: scale,
            representationTypes: .thumbnail
        )

        let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)

        guard let data = representation.uiImage.jpegData(compressionQuality: 0.85) else {
            throw EvidenceImageDataProviderError.failedToLoadImageData
        }

        return data
    }
}
