import AVFoundation
import Kingfisher
import PolkadotUI
import UIKit

protocol AVPlayerItemProvider {
    func playerItem() -> AVPlayerItem
}

final class IPFSVideoSource {
    private enum Constants {
        static let customScheme = "ipfs"
    }

    let identifier: String

    private let delegate: IPFSResourceLoaderDelegate
    private let asset: AVURLAsset
    private let logger: LoggerProtocol

    init?(
        manifestURL: URL,
        logger: LoggerProtocol = Logger.shared
    ) {
        identifier = manifestURL.absoluteString
        self.logger = logger

        let delegate = IPFSResourceLoaderDelegate(
            manifestURL: manifestURL,
            loadingCompletion: { _ in }
        )
        self.delegate = delegate

        var components = URLComponents()
        components.scheme = Constants.customScheme
        components.host = manifestURL.lastPathComponent

        guard let assetURL = components.url else {
            return nil
        }

        let asset = AVURLAsset(url: assetURL)
        asset.resourceLoader.setDelegate(delegate, queue: .main)
        self.asset = asset
    }
}

// MARK: - AVPlayerItemProvider

extension IPFSVideoSource: AVPlayerItemProvider {
    func playerItem() -> AVPlayerItem {
        AVPlayerItem(asset: asset)
    }
}

// MARK: - ChatMessageMediaPreviewProviding

extension IPFSVideoSource: ChatMessageMediaPreviewProviding {
    @MainActor
    func providePreview(for imageView: UIImageView, size: CGSize?) {
        let resolvedSize = size ?? CGSize(width: 512, height: 512)

        let provider = IPFSVideoThumbnailProvider(
            asset: asset,
            identifier: identifier,
            targetSize: resolvedSize,
            logger: logger
        )

        var options: KingfisherOptionsInfo = [
            .scaleFactor(UIScreen.main.scale),
            .cacheOriginalImage,
            .transition(.fade(0.25))
        ]

        let processor = DownsamplingImageProcessor(size: resolvedSize)
        options.append(.processor(processor))

        imageView.kf.setImage(with: provider, options: options) { [weak self] result in
            switch result {
            case .success:
                self?.logger.debug("Successfully loaded IPFS video thumbnail")
            case let .failure(error):
                self?.logger.error("Failed to load IPFS video thumbnail: \(error)")
            }
        }
    }
}
