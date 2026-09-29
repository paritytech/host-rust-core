import AVFoundation
import PolkadotUI

enum IPFSResourceLoaderError: Error {
    case invalidURL
    case fetchFailed
    case internalError
    case unknown(Error)
}

final class IPFSResourceLoaderDelegate: NSObject {
    private let manifestURL: URL
    private let dataStreamer: IPFSDataStreaming
    private var manifest: IPFSManifest?
    private let logger: LoggerProtocol
    private var loadingCompletion: ((LoadingState) -> Void)?
    private let loadingInformationQueue: DispatchQueue

    private var executingRequests: [UUID: AVAssetResourceLoadingRequest] = [:]

    init(
        manifestURL: URL,
        loadingCompletion: @escaping (LoadingState) -> Void,
        logger: LoggerProtocol = Logger.shared,
        loadingInformationQueue: DispatchQueue = .main
    ) {
        self.manifestURL = manifestURL
        dataStreamer = IPFSDataStreamer(manifestURL: manifestURL)
        self.loadingCompletion = loadingCompletion
        self.logger = logger
        self.loadingInformationQueue = loadingInformationQueue
        super.init()
    }

    private func handleMetadataRequestCompletion(result: Result<IPFSStreamingMetadata, Error>, for requestId: UUID) {
        guard let loadingRequest = executingRequests[requestId] else {
            return
        }

        switch result {
        case let .success(metadata):
            let contentInformationRequest = loadingRequest.contentInformationRequest
            contentInformationRequest?.contentType = AVFileType.mov.rawValue // TODO: Detect codec type automatically
            contentInformationRequest?.contentLength = Int64(metadata.manifest.totalSize)
            contentInformationRequest?.isByteRangeAccessSupported = true

            if let dataRequest = loadingRequest.dataRequest {
                startDataRequest(dataRequest, requestId: requestId)
            } else {
                completeRequest(for: requestId, error: nil)
            }

        case let .failure(error):
            completeRequest(for: requestId, error: error)
        }
    }

    private func handleDataRequestCompletion(result: Result<Void, Error>, for requestId: UUID) {
        switch result {
        case .success:
            completeRequest(for: requestId, error: nil)
        case let .failure(error):
            completeRequest(for: requestId, error: error)
        }
    }

    private func startDataRequest(_ dataRequest: AVAssetResourceLoadingDataRequest, requestId: UUID) {
        dataStreamer.executeData(request: .init(
            requestId: requestId,
            startOffset: dataRequest.requestedOffset,
            length: dataRequest.requestedLength,
            onNextData: { [weak self] data in
                guard let self else {
                    return
                }

                loadingInformationQueue.async {
                    dataRequest.respond(with: data)
                }
            }, onCompletion: { [weak self] result in
                guard let self else {
                    return
                }

                loadingInformationQueue.async {
                    self.handleDataRequestCompletion(result: result, for: requestId)
                }
            }
        ))
    }

    private func clearRequest(for requestId: UUID, error: Error?) {
        let wasLoading = !executingRequests.isEmpty

        executingRequests[requestId] = nil

        let isLoading = !executingRequests.isEmpty

        if wasLoading, let error {
            loadingCompletion?(.error(error))
        } else if wasLoading, !isLoading {
            loadingCompletion?(.finished)
        }
    }

    private func completeRequest(for requestId: UUID, error: Error?) {
        let request = executingRequests[requestId]

        clearRequest(for: requestId, error: error)

        if let error {
            request?.finishLoading(with: error)
        } else {
            request?.finishLoading()
        }
    }

    private func addRequest(_ request: AVAssetResourceLoadingRequest, requestId: UUID) {
        let wasLoading = !executingRequests.isEmpty

        executingRequests[requestId] = request

        let isLoading = !executingRequests.isEmpty

        if !wasLoading, isLoading {
            loadingCompletion?(.loading)
        }
    }
}

extension IPFSResourceLoaderDelegate: AVAssetResourceLoaderDelegate {
    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        loadingInformationQueue.async { [weak self] in
            guard let self else {
                return
            }

            logger.debug("New request: \(loadingRequest)")

            let requestId = UUID()

            if loadingRequest.contentInformationRequest != nil {
                addRequest(loadingRequest, requestId: requestId)

                dataStreamer.executeMetadata(request: .init(
                    requestId: requestId,
                    onCompletion: { [weak self] result in
                        guard let self else {
                            return
                        }

                        loadingInformationQueue.async {
                            self.handleMetadataRequestCompletion(result: result, for: requestId)
                        }
                    }
                ))
            } else if let dataRequest = loadingRequest.dataRequest {
                addRequest(loadingRequest, requestId: requestId)

                startDataRequest(dataRequest, requestId: requestId)
            } else {
                logger.warning("No content or data request")
                loadingRequest.finishLoading()
            }
        }

        return true
    }

    func resourceLoader(_: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        loadingInformationQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard let requestId = executingRequests.first(where: { $0.value === loadingRequest })?.key else {
                return
            }

            clearRequest(for: requestId, error: nil)
            dataStreamer.cancelRequest(for: requestId)
        }
    }
}
