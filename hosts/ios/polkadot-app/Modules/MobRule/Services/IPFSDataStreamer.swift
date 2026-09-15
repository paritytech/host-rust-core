import Foundation
import BulletinChain
import Operation_iOS

struct IPFSDataStreamingRequest {
    let requestId: UUID
    let startOffset: Int64
    let length: Int
    let onNextData: (Data) -> Void
    let onCompletion: (Result<Void, Error>) -> Void

    var endOffset: Int64 {
        startOffset + Int64(length) - 1
    }
}

struct IPFSStreamingMetadata {
    let manifest: IPFSManifest
    let chunkSize: Int
}

struct IPFSMetadataRequest {
    let requestId: UUID
    let onCompletion: (Result<IPFSStreamingMetadata, Error>) -> Void
}

protocol IPFSDataStreaming: AnyObject {
    func executeMetadata(request: IPFSMetadataRequest)
    func executeData(request: IPFSDataStreamingRequest)
    func cancelRequest(for requestId: UUID)
}

enum IPFSDataStreamingError: Error {
    case noChunks
    case urlNotDerived(String)
    case invalidDataRange(Int, IPFSDataStreamingRequest, IPFSStreamingMetadata, Data)
    case invalidRequest(IPFSDataStreamingRequest)
}

///  Class is designed to provide IPFS chunks loading based on the metadata file (manifest).
///
///  Interface supports: fetching metadata file (see executeMetadata) and fetching a range of bytes of the original file
/// (see executeData).
///  It also supports requests cancellation based on requestId (see cancelRequest).
///
///  The logic for fetching range of bytes first ensures that the metadata is loaded (and triggers loading if not). This
/// allows to understand
///   the list of available chunks and chunk size. Then the logic derives the chunk indexes for the range of bytes and
/// starts loading
///   chunks itself. Once a chunk is loaded it is provided to the request's onNextData closure. Note that despite of the
/// fact that
///   chunks are loaded in parallel the logic ensures that the onNextData is called sequentially starting from the lower
/// chunk index.
///   Finally, request's onCompletion closure is called when all chunks are loaded.
///
///   Note that the class supports requesting multiple bytes ranges at the same time.
final class IPFSDataStreamer {
    private let manifestURL: URL
    private let hashConverter: HexToCIDConverting
    private let urlSession: URLSession
    private let logger: LoggerProtocol
    private let operationQueue: OperationQueue
    private let syncQueue: DispatchQueue

    private var metadataResult: Result<IPFSStreamingMetadata, Error>?

    private var pendingRequests: [IPFSDataStreamingRequest] = []
    private var executingRequests: [UUID: CancellableCallStore] = [:]
    private var pendingMetadataRequests: [IPFSMetadataRequest] = []

    private var setupCancellable = CancellableCallStore()

    init(
        manifestURL: URL,
        hashConverter: HexToCIDConverting = HexToCIDConverter(),
        urlSession: URLSession = URLSession.videoStreamingSession(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        syncQueue: DispatchQueue = DispatchQueue(label: "io.web3citezenship.ipfs.streamer"),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.manifestURL = manifestURL
        self.hashConverter = hashConverter
        self.urlSession = urlSession
        self.operationQueue = operationQueue
        self.syncQueue = syncQueue
        self.logger = logger
    }

    deinit {
        setupCancellable.cancel()
    }

    private func createManifestOperation(from manifestURL: URL) -> BaseOperation<IPFSManifest> {
        let operation = NetworkOperation<IPFSManifest>(
            requestFactory: BlockNetworkRequestFactory {
                URLRequest(url: manifestURL, cachePolicy: .returnCacheDataElseLoad)
            },
            resultFactory: AnyNetworkResultFactory { data in
                try JSONDecoder().decode(IPFSManifest.self, from: data)
            }
        )

        operation.networkSession = urlSession

        return operation
    }

    private func createFirstChunkOperation(
        dependingOn manifestOperation: BaseOperation<IPFSManifest>,
        hashConverter: HexToCIDConverting
    ) -> BaseOperation<Data> {
        let operation = NetworkOperation<Data>(
            requestFactory: BlockNetworkRequestFactory { [weak self] in
                let manifest = try manifestOperation.extractNoCancellableResultData()

                self?.logger.debug("Did load manifest \(manifest)")

                guard !manifest.chunks.isEmpty else {
                    throw IPFSDataStreamingError.noChunks
                }

                guard let segmentUrl = hashConverter.convertToIPFSURL(fileHash: manifest.chunks[0], codec: .raw) else {
                    throw IPFSDataStreamingError.urlNotDerived(manifest.chunks[0])
                }

                return URLRequest(url: segmentUrl, cachePolicy: .returnCacheDataElseLoad)
            },
            resultFactory: AnyNetworkResultFactory { data in
                data
            }
        )

        operation.networkSession = urlSession

        return operation
    }

    private func setup(for manifestURL: URL, hashConverter: HexToCIDConverting) {
        logger.debug("Setuping streaming for manifest \(manifestURL)")

        let manifestOperation = createManifestOperation(from: manifestURL)

        let firstChunkOperation = createFirstChunkOperation(
            dependingOn: manifestOperation,
            hashConverter: hashConverter
        )

        firstChunkOperation.addDependency(manifestOperation)

        let combiningOperation = ClosureOperation<IPFSStreamingMetadata> {
            let manifest = try manifestOperation.extractNoCancellableResultData()
            let chunk = try firstChunkOperation.extractNoCancellableResultData()

            return .init(manifest: manifest, chunkSize: chunk.count)
        }

        combiningOperation.addDependency(firstChunkOperation)

        let wrapper = CompoundOperationWrapper(
            targetOperation: combiningOperation,
            dependencies: [manifestOperation, firstChunkOperation]
        )

        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: setupCancellable,
            runningCallbackIn: syncQueue
        ) { [weak self] result in
            switch result {
            case let .success(metadata):
                self?.logger.debug("Did complete setup for \(manifestURL): \(metadata.chunkSize)")
            case let .failure(error):
                self?.logger.error("Did fail setup \(manifestURL): \(error)")
            }

            self?.metadataResult = result
            self?.notifyAllMetadataRequests(with: result)
            self?.startServingRequests(for: result)
        }
    }

    private func startServingRequests(for result: Result<IPFSStreamingMetadata, Error>) {
        switch result {
        case let .success(metadata):
            startServingRequests(for: metadata)
        case let .failure(error):
            notifyAllDataRequests(with: error)
        }
    }

    private func startServingRequests(for metadata: IPFSStreamingMetadata) {
        let requests = pendingRequests
        pendingRequests = []

        requests.forEach { execute(request: $0, metadata: metadata) }
    }

    private func notifyAllDataRequests(with error: Error) {
        let requests = pendingRequests
        pendingRequests = []

        requests.forEach { $0.onCompletion(.failure(error)) }
    }

    private func notifyAllMetadataRequests(with result: Result<IPFSStreamingMetadata, Error>) {
        let requests = pendingMetadataRequests
        pendingMetadataRequests = []

        requests.forEach { $0.onCompletion(result) }
    }

    private func execute(request: IPFSDataStreamingRequest, metadata: IPFSStreamingMetadata) {
        guard request.startOffset >= 0, request.endOffset < metadata.manifest.totalSize else {
            request.onCompletion(.failure(IPFSDataStreamingError.invalidRequest(request)))
            return
        }

        guard request.length > 0 else {
            request.onCompletion(.success(()))
            return
        }

        let startChunkIndex = IPFSChunkMapper.getStartChunkIndex(from: request, chunkSize: metadata.chunkSize)
        let endChunkIndex = IPFSChunkMapper.getEndChunkIndex(from: request, chunkSize: metadata.chunkSize)

        logger.debug("Will load chunks from \(startChunkIndex) to \(endChunkIndex) for \(request.requestId)")

        let wrapper: CompoundOperationWrapper<Void>? = (startChunkIndex ... endChunkIndex)
            .reduce(nil) { currentWrapper, chunkIndex in
                let nextWrapper = createChunkWrapper(
                    for: chunkIndex,
                    request: request,
                    previousWrapper: currentWrapper,
                    metadata: metadata,
                    hashConverter: hashConverter
                )

                if let currentWrapper {
                    return nextWrapper.insertingHead(operations: currentWrapper.allOperations)
                } else {
                    return nextWrapper
                }
            }

        guard let wrapper else {
            request.onCompletion(.success(()))
            return
        }

        let callStore = CancellableCallStore()

        executingRequests[request.requestId] = callStore

        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: callStore,
            runningCallbackIn: syncQueue
        ) { [weak self] result in
            guard let self, executingRequests[request.requestId] != nil else {
                return
            }

            logger.debug("Completing request \(request.requestId)")

            executingRequests[request.requestId] = nil
            request.onCompletion(result)
        }
    }

    private func createChunkWrapper(
        for index: Int,
        request: IPFSDataStreamingRequest,
        previousWrapper: CompoundOperationWrapper<Void>?,
        metadata: IPFSStreamingMetadata,
        hashConverter: HexToCIDConverting
    ) -> CompoundOperationWrapper<Void> {
        logger.debug("Will schedule chunk(\(index)) for request: \(request.requestId)")

        let chunkOperation = NetworkOperation<Data>(
            requestFactory: BlockNetworkRequestFactory {
                guard let segmentUrl = hashConverter.convertToIPFSURL(
                    fileHash: metadata.manifest.chunks[index],
                    codec: .raw
                )
                else {
                    throw IPFSDataStreamingError.urlNotDerived(metadata.manifest.chunks[index])
                }

                return URLRequest(url: segmentUrl, cachePolicy: .returnCacheDataElseLoad)
            },
            resultFactory: AnyNetworkResultFactory { data in
                data
            }
        )

        let chunkNotification = ClosureOperation { [weak self] in
            guard let self else {
                return
            }

            // make sure previous chunk notified
            try previousWrapper?.targetOperation.extractNoCancellableResultData()

            let chunkData = try chunkOperation.extractNoCancellableResultData()

            logger.debug("Did receive chunk(\(index)) size=\(chunkData.count) for \(request.requestId)")

            guard
                let range = IPFSChunkMapper.getChunkDataRange(
                    for: index,
                    request: request,
                    chunkSize: metadata.chunkSize,
                    resultSize: chunkData.count
                ) else {
                throw IPFSDataStreamingError.invalidDataRange(index, request, metadata, chunkData)
            }

            let responseData = chunkData.subdata(in: range)

            logger.debug("Responding with range \(range) for \(request.requestId)")

            syncQueue.async {
                request.onNextData(responseData)
            }
        }

        chunkNotification.addDependency(chunkOperation)

        if let prevChunkNotification = previousWrapper?.targetOperation {
            chunkOperation.addDependency(prevChunkNotification)
        }

        return CompoundOperationWrapper(targetOperation: chunkNotification, dependencies: [chunkOperation])
    }
}

extension IPFSDataStreamer: IPFSDataStreaming {
    func executeMetadata(request: IPFSMetadataRequest) {
        syncQueue.async { [weak self] in
            guard let self else {
                return
            }

            logger.debug("New metadata request: \(request.requestId)")

            switch metadataResult {
            case let .success(metadata):
                request.onCompletion(.success(metadata))
            case .failure:
                metadataResult = nil
                pendingMetadataRequests.append(request)
                setup(for: manifestURL, hashConverter: hashConverter)
            case .none:
                pendingMetadataRequests.append(request)

                if !setupCancellable.hasCall {
                    setup(for: manifestURL, hashConverter: hashConverter)
                }

                logger.debug("Save metadata request as pending \(request.requestId)")
            }
        }
    }

    func executeData(request: IPFSDataStreamingRequest) {
        syncQueue.async { [weak self] in
            guard let self else {
                return
            }

            logger.debug("New data request: \(request.requestId) start=\(request.startOffset) length=\(request.length)")

            switch metadataResult {
            case let .success(metadata):
                execute(request: request, metadata: metadata)
            case .failure:
                // retry setup
                metadataResult = nil
                pendingRequests.append(request)
                setup(for: manifestURL, hashConverter: hashConverter)
            case .none:
                pendingRequests.append(request)

                if !setupCancellable.hasCall {
                    setup(for: manifestURL, hashConverter: hashConverter)
                }

                logger.debug("Save data request as pending \(request.requestId)")
            }
        }
    }

    func cancelRequest(for requestId: UUID) {
        syncQueue.async { [weak self] in
            guard let self else {
                return
            }

            pendingRequests = pendingRequests.filter { $0.requestId != requestId }
            pendingMetadataRequests = pendingMetadataRequests.filter { $0.requestId != requestId }

            let store = executingRequests[requestId]
            executingRequests[requestId] = nil
            store?.cancel()

            logger.debug("Request cancelled: \(requestId)")
        }
    }
}
