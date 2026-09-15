import Foundation
import UIKit
import PolkadotUI
import QuickLookThumbnailing
import Kingfisher

enum EvidenceImageDataProviderError: Error {
    case fileNotFound
    case failedToLoadImageData
    case failedToGenerateThumbnail
}

enum EvidenceMediaType {
    case video
    case photo
}

final class EvidenceMessageMediaPreviewProvider {
    private let type: EvidenceMediaType
    private let fileManager: EvidenceFileManaging
    private let optionsFactory: ImageProcessingOptionsProducing
    private let logger: LoggerProtocol

    init(
        type: EvidenceMediaType,
        fileManager: EvidenceFileManaging,
        optionsFactory: ImageProcessingOptionsProducing = ImageProcessingOptionsFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.type = type
        self.fileManager = fileManager
        self.optionsFactory = optionsFactory
        self.logger = logger
    }
}

extension EvidenceMessageMediaPreviewProvider: ChatMessageMediaPreviewProviding {
    var identifier: String {
        switch type {
        case .video:
            fileManager.videoDirectory.path
        case .photo:
            fileManager.photoDirectory.path
        }
    }

    func providePreview(for imageView: UIImageView, size: CGSize?) {
        Task { @MainActor in
            do {
                let url: URL =
                    switch type {
                    case .video:
                        try fileManager.existingVideoExport() ?? fileManager.prepareVideoExport()
                    case .photo:
                        try fileManager.preparePhotoEvidenceUrl()
                    }

                let resolvedSize = size ?? CGSize(width: 512, height: 512)

                let provider = EvidenceImageDataProvider(
                    mediaType: type,
                    url: url,
                    targetSize: resolvedSize,
                    logger: logger
                )

                let settings = ImageViewModelSettings(targetSize: resolvedSize)
                let options = optionsFactory.options(for: settings, animated: true)

                imageView.kf.setImage(with: provider, options: options) { [weak self] result in
                    switch result {
                    case .success:
                        self?.logger.debug("Successfully loaded evidence preview")
                    case let .failure(error):
                        self?.logger.error("Failed to load evidence preview: \(error)")
                    }
                }
            } catch {
                logger.error("Failed to prepare evidence preview: \(error)")
            }
        }
    }
}
