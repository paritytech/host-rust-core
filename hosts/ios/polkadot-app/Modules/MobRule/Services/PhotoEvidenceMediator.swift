import Foundation
import BulletinChain
import Kingfisher
import PolkadotUI
import UIKit

enum IPFSImageLoadingError: Error {
    case internalError
    case unknown(Error)
}

final class PhotoEvidenceMediator {
    private let manifestURL: URL
    private let logger: LoggerProtocol
    private let urlSession: URLSessionProtocol
    private let hashConverter: HexToCIDConverting

    init(
        manifestURL: URL,
        hashConverter: HexToCIDConverting = HexToCIDConverter(),
        urlSession: URLSessionProtocol = URLSession.shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.manifestURL = manifestURL
        self.hashConverter = hashConverter
        self.urlSession = urlSession
        self.logger = logger
    }
}

// MARK: - ChatMessageMediaPreviewProviding

extension PhotoEvidenceMediator: ChatMessageMediaPreviewProviding {
    var identifier: String {
        manifestURL.absoluteString
    }

    func providePreview(for imageView: UIImageView, size: CGSize?) {
        fetchManifest(with: manifestURL) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(manifest):
                loadImage(from: manifest, into: imageView, size: size)
            case let .failure(error):
                logger.error("Failed to load evidence preview: \(error)")
            }
        }
    }
}

// MARK: - Private

private extension PhotoEvidenceMediator {
    func fetchManifest(
        with manifestURL: URL,
        completion: @escaping (Result<IPFSManifest, IPFSImageLoadingError>) -> Void
    ) {
        logger.debug("Fetching metadata from URL: \(manifestURL)")
        let dataTask = urlSession.dataTask(with: manifestURL) { [weak self] data, _, error in
            guard let self else { return }
            if let data {
                do {
                    let manifest = try JSONDecoder().decode(IPFSManifest.self, from: data)
                    logger.debug("Metadata decoded successfully: \(manifest)")
                    completion(.success(manifest))
                } catch {
                    logger.error("Error decoding metadata: \(error)")
                    completion(.failure(.unknown(error)))
                }
            } else {
                logger.error("Error fetching manifest from URL: \(manifestURL), error: \(String(describing: error))")
                completion(.failure(.internalError))
            }
        }
        dataTask.resume()
    }

    func loadImage(from manifest: IPFSManifest, into imageView: UIImageView, size: CGSize?) {
        guard let imageChunk = manifest.chunks.first,
              let imageURL = hashConverter.convertToIPFSURL(fileHash: imageChunk, codec: .raw) else {
            logger.error("Could not generate URL for photo from manifest: \(manifest)")
            return
        }

        var options: KingfisherOptionsInfo = [
            .scaleFactor(UIScreen.main.scale),
            .cacheOriginalImage,
            .transition(.fade(0.25))
        ]

        if let size {
            let processor = DownsamplingImageProcessor(size: size)
            options.append(.processor(processor))
        }

        DispatchQueue.main.async { [weak self] in
            imageView.kf.setImage(with: imageURL, options: options) { result in
                switch result {
                case .success:
                    self?.logger.debug("Successfully loaded IPFS evidence preview")
                case let .failure(error):
                    self?.logger.error("Failed to load IPFS evidence preview: \(error)")
                }
            }
        }
    }
}
