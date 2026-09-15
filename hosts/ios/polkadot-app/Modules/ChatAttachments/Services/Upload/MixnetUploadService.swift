import Foundation
import HandoffService
import Operation_iOS
import CommonService
import AsyncExtensions
import KeyDerivation
import SubstrateSdk
import NovaCrypto
import StructuredConcurrency
import Individuality

protocol AttachmentUploadingServicing: AttachmentLoadProgressProvidable, ApplicationServiceProtocol {}

final class MixnetUploadService: @unchecked Sendable {
    static let retryMaxAttempts = 5
    static let retryInitialDelay: Duration = .seconds(2)

    let loaderFactory: HOPFileLoaderMaking
    let messageProviderFactory: ChatMessageDataProviderMaking
    let uploadContextFactory: UploadFileContextFactory
    let logger: LoggerProtocol

    let context: MixnetUploadContext
    let senderProvider: AttachmentsSenderProviding
    let allowanceManager: AllowanceManaging

    private var uploadTask: Task<Void, Never>?

    init(
        loaderFactory: HOPFileLoaderMaking,
        storageFacade: StorageFacadeProtocol,
        uploadContextFactory: UploadFileContextFactory,
        senderProvider: AttachmentsSenderProviding,
        allowanceManager: AllowanceManaging,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.loaderFactory = loaderFactory
        self.senderProvider = senderProvider
        self.allowanceManager = allowanceManager
        self.uploadContextFactory = uploadContextFactory

        let repositoryFactory = ChatMessageRepositoryFactory(storageFacade: storageFacade)

        messageProviderFactory = ChatMessageDataProviderFactory(
            repositoryFactory: repositoryFactory,
            operationQueue: operationQueue,
            logger: logger
        )

        let attachmentUpdateRepository = storageFacade.createRepository(
            mapper: AnyCoreDataMapper(AttachmentUploadingMapper())
        )

        context = MixnetUploadContext(
            repository: AnyDataProviderRepository(attachmentUpdateRepository),
            logger: logger
        )

        self.logger = logger
    }
}

extension MixnetUploadService: AttachmentUploadingServicing {
    func setup() {
        startUploading()
    }

    func throttle() {
        uploadTask?.cancel()
        cancelAllUploading()
    }

    func subscribeState(for attachmentId: AttachmentId) async -> AnyAsyncSequence<AttachmentProgressEvent?> {
        await context.subscribeState(for: attachmentId)
    }
}

private extension MixnetUploadService {
    func cancelAllUploading() {
        Task { [context] in
            await context.cancelAll()
        }
    }

    func performUploadingIfNeeded(for uploadData: MixnetUploadData) async {
        await context.processUploadData(
            for: uploadData
        ) { [logger, loaderFactory, uploadContextFactory, senderProvider, allowanceManager, weak self] in
            Task {
                do {
                    try await markStallActivity("Sending attachment") {
                        guard let store = uploadContextFactory.createContext(
                            attachmentId: uploadData.attachmentId
                        ) else {
                            logger.error("Failed to create upload context for \(uploadData.attachmentId.fileId)")
                            return
                        }

                        let credentials = try await store.ensureUploadCredentials()

                        let fileLoader = try loaderFactory.makeLoader(for: credentials.node)
                        let recipients = try FileRecipients(ticket: credentials.ticket)

                        let proofWallet = try await senderProvider.getWallet(for: uploadData.chatId)

                        let accountId = try proofWallet.getRawPublicKey()
                        try await allowanceManager.ensureCanSubmit(accountId: accountId, priority: .normal)

                        let sender = try proofWallet.getMultiSigner()
                        let proofProvider = SenderProofProvider(sender: sender) { data in
                            try proofWallet.sign(data: data)
                        }

                        let uploadingStream = fileLoader.uploadFile(
                            store: store,
                            sender: proofProvider,
                            recipients: recipients
                        )

                        try await markStallRegion("Uploading file") {
                            for try await event in uploadingStream {
                                try await self?.handleUploadingEvent(
                                    event,
                                    uploadData: uploadData,
                                    ticket: credentials.ticket,
                                    node: credentials.node
                                )
                            }
                        }
                    }

                    logger.debug("Task completed successfully")
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    logger.error("Task completed with error: \(error)")

                    await self?.context.handle(
                        uploadEvent: .onFailure(error),
                        attachmentId: uploadData.attachmentId
                    )
                }
            }
        }
    }

    func handleUploadingEvent(
        _ event: FileUploadingEvent,
        uploadData: MixnetUploadData,
        ticket: FileTicket,
        node: ChatRemoteMessageContent.NodeEndpoint
    ) async throws {
        switch event {
        case let .onProgress(progress):
            let fileId = uploadData.attachmentId.fileId
            logger
                .debug(
                    "\(fileId): \(progress.uploaded) out of \(progress.total) uploaded"
                )

            await context.handle(
                uploadEvent: .onProgress(
                    .init(
                        uploaded: progress.uploaded,
                        total: progress.total
                    )
                ),
                attachmentId: uploadData.attachmentId
            )
        case let .onFinished(finished):
            logger.debug("Finished uploading")

            await context.handle(
                uploadEvent: .onComplete(
                    .toPeer(
                        .init(
                            identifier: finished.entryHash,
                            claimTicket: ticket,
                            node: node
                        )
                    )
                ),
                attachmentId: uploadData.attachmentId
            )
        case let .onError(error):
            logger.error("Uploading failed: \(error)")
            await context.handle(
                uploadEvent: .onFailure(error),
                attachmentId: uploadData.attachmentId
            )

            throw error
        }
    }

    func startUploading() {
        uploadTask = Task { [messageProviderFactory, logger] in
            do {
                try await withRetry(
                    maxAttempts: MixnetUploadService.retryMaxAttempts,
                    initialDelay: MixnetUploadService.retryInitialDelay
                ) { [weak self] in
                    let stream = messageProviderFactory.subscribeMessages(
                        with: .newLocalDeviceOutgoingRemoteRichTextMessages()
                    )

                    logger.debug("Starting messages stream")

                    for try await messages in stream {
                        let uploadList = messages.flatMap { message in
                            MixnetUploadList.createUploadList(from: message)
                        }

                        for uploadData in uploadList {
                            await self?.performUploadingIfNeeded(for: uploadData)
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                logger.error("Task failed: \(error)")
            }
        }
    }
}
