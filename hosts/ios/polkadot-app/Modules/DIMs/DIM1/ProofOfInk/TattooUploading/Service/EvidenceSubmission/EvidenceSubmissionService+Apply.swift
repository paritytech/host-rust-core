import BulletinChain
import Foundation
import SubstrateSdk
import ExtrinsicService
import Operation_iOS
import Individuality
import ChainRegistry

extension EvidenceSubmissionService {
    func applySubmissionAllocation(
        for local: EvidenceSubmission.LocalState,
        session: EvidenceSubmission.Session,
        allocation: ProofOfInkPallet.Allocation,
        remote: EvidenceSubmission.RemoteState?
    ) {
        guard let candidate = remote?.candidate else {
            logger.error("Expected non null candidate")
            return
        }

        guard case let .selected(selectedCandidate) = candidate else {
            logger.error("Expected selected candidate")
            return
        }

        let evidenceId = String(selectedCandidate.since)
        let evidenceManager = evidenceFileManagerFactory.createManager(evidenceId: evidenceId)
        let candidateType = PersonRegistration.CandidateType(candidate: candidate)

        switch allocation {
        case .initial:
            guard
                let fileMetadata = EvidenceSubmission.FileMetadata(
                    baseUrl: evidenceManager.photoDirectory,
                    name: local.photoName,
                    allocation: allocation,
                    mediaId: local.photoId
                ) else {
                updateSession(error: .chunksLoading)
                return
            }

            applyMediaAllocation(
                for: session,
                remote: remote,
                fileMetadata: fileMetadata,
                candidateType: candidateType
            )
        case .initDone:
            logger.debug("Photo judging completed. Allocating storage for the video...")
            let resubmittingIfNoHash = peopleExtrinsicSubmissionFactory == nil
            let canAllocateFull = session.progress?
                .checkCanAllocateFull(resubmittingIfNoHash: resubmittingIfNoHash) ?? true

            if canAllocateFull {
                allocateFull(
                    for: local.videoId,
                    currentAuthorization: remote?.transactionStorageAuthorizations,
                    candidateType: candidateType
                )
            }
        case .full:
            guard
                let fileMetadata = EvidenceSubmission.FileMetadata(
                    baseUrl: evidenceManager.videoDirectory,
                    name: local.videoName,
                    allocation: allocation,
                    mediaId: local.videoId
                ) else {
                updateSession(error: .chunksLoading)
                return
            }

            applyMediaAllocation(
                for: session,
                remote: remote,
                fileMetadata: fileMetadata,
                candidateType: candidateType
            )
        }
    }

    func applyMediaAllocation(
        for session: EvidenceSubmission.Session,
        remote: EvidenceSubmission.RemoteState?,
        fileMetadata: EvidenceSubmission.FileMetadata,
        candidateType: PersonRegistration.CandidateType
    ) {
        guard
            let authorization = remote?.transactionStorageAuthorizations,
            let blockNumber = remote?.bulletInBlockNumber else {
            return
        }

        if let sessionMediaId = session.mediaId, sessionMediaId != fileMetadata.mediaId {
            logger.error("Ready to submit \(fileMetadata.mediaId) but found \(sessionMediaId)")
            updateSession(error: .mediaMismatch)
            return
        }

        guard remote?.candidate != nil else {
            logger.error("Expected non null candidate")
            return
        }

        applySubmissionFile(
            for: authorization,
            bulletInBlock: blockNumber,
            progress: session.progress ?? .waiting,
            fileMetadata: fileMetadata,
            candidateType: candidateType
        )
    }

    func applySubmissionFile(
        for authorization: TransactionStoragePallet.Authorization,
        bulletInBlock: BlockNumber,
        progress: EvidenceSubmission.Progress,
        fileMetadata: EvidenceSubmission.FileMetadata,
        candidateType: PersonRegistration.CandidateType
    ) {
        switch progress {
        case let .allocatingFull(allocatingFull):
            // allocated new storage

            if
                let previousAllowedTransactions = allocatingFull.previousAllowedTransactions,
                authorization.extent.transactions <= previousAllowedTransactions {
                logger.debug("Still waiting storage to apply")
                return
            }

            validateAndSubmitChunk(
                for: 0,
                fileMetadata: fileMetadata,
                authorization: authorization,
                bulletInBlock: bulletInBlock,
                chunkSize: maxChunkSize
            )

        case .waiting:
            // just commited

            validateAndSubmitChunk(
                for: 0,
                fileMetadata: fileMetadata,
                authorization: authorization,
                bulletInBlock: bulletInBlock,
                chunkSize: maxChunkSize
            )

        case let .submitting(submitting):
            if progress.checkCanSubmitChunk(resubmittingIfNoHash: bulletinExtrinsicService == nil) {
                // nothing is currently is being submitted
                validateAndSubmitChunk(
                    for: submitting.chunkIndex,
                    fileMetadata: fileMetadata,
                    authorization: authorization,
                    bulletInBlock: bulletInBlock,
                    chunkSize: submitting.chunkSize
                )
            } else if submitting.checkCommitment(for: authorization) {
                // submission appeared onchain, go to the next one
                if submitting.isLastChunk {
                    completeEvidenceSubmission(
                        using: fileMetadata,
                        chunkSize: submitting.chunkSize,
                        candidateType: candidateType
                    )
                } else {
                    let nextIndex = submitting.chunkIndex + 1

                    validateAndSubmitChunk(
                        for: nextIndex,
                        fileMetadata: fileMetadata,
                        authorization: authorization,
                        bulletInBlock: bulletInBlock,
                        chunkSize: submitting.chunkSize
                    )
                }
            }

        case let .completing(completing):
            if progress
                .checkCanCompleteEvidenceSubmission(resubmittingIfNoHash: peopleExtrinsicSubmissionFactory == nil) {
                completeEvidenceSubmission(
                    using: fileMetadata,
                    chunkSize: completing.chunkSize,
                    candidateType: candidateType
                )
            } else {
                logger.debug("Waiting evidence submission completion")
            }
        }
    }

    func validateAndSubmitChunk(
        for index: Int,
        fileMetadata: EvidenceSubmission.FileMetadata,
        authorization: TransactionStoragePallet.Authorization,
        bulletInBlock: BlockNumber,
        chunkSize: UInt64
    ) {
        guard let chunks = try? getChunks(for: fileMetadata, maxChunkSize: chunkSize) else {
            logger.error("Chunks loading failed")
            updateSession(error: .chunksLoading)
            return
        }

        guard
            authorization.extent.transactions > 0,
            calculatedRemainedSize(for: chunks, currentIndex: index) <= authorization.extent.bytes else {
            logger.error("Not enough space allocated")
            updateSession(error: .notEnoughStorage)
            return
        }

        guard bulletInBlock < authorization.expiration else {
            logger.error("Allocation expired")
            updateSession(error: .storageExpired)
            return
        }

        submitChunk(
            for: chunks,
            index: index,
            fileMetadata: fileMetadata,
            authorization: authorization
        )
    }

    func submitChunk(
        for chunks: [Data],
        index: Int,
        fileMetadata: EvidenceSubmission.FileMetadata,
        authorization: TransactionStoragePallet.Authorization
    ) {
        guard
            let extrinsicService = getBulletInChainExtrinsicService(),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: AppConfig.Chains.bulletInChain) else {
            logger.warning("Bulletin extrinsic service not ready")
            return
        }

        logger.debug("Submitting chunk \(index + 1) of \(chunks.count)")

        let chunk = chunks[index]

        let submitting = EvidenceSubmission.Progress.Submitting(
            chunkSize: UInt64(chunk.count),
            chunkIndex: index,
            totalChunks: chunks.count,
            remoteRemainedBefore: authorization.extent.bytes,
            txHash: nil
        )

        let progress = EvidenceSubmission.Progress.submitting(submitting)
        updateSession(progress: progress, mediaId: fileMetadata.mediaId)

        serializeChunkAndSubmit(
            for: chunk,
            extrinsicService: extrinsicService,
            runtimeProvider: runtimeProvider,
            submitting: submitting,
            fileMetadata: fileMetadata
        )
    }

    func serializeChunkAndSubmit(
        for chunk: Data,
        extrinsicService: ExtrinsicServiceProtocol,
        runtimeProvider: RuntimeProviderProtocol,
        submitting: EvidenceSubmission.Progress.Submitting,
        fileMetadata: EvidenceSubmission.FileMetadata
    ) {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        execute(
            operation: codingFactoryOperation,
            inOperationQueue: operationQueue,
            runningCallbackIn: syncQueue
        ) { [weak self] result in
            switch result {
            case let .success(codingFactory):
                do {
                    let call = TransactionStoragePallet.StoreCall(data: chunk)
                    let encodedCall = try EvidenceChunkCallEncoder().encode(
                        call: call,
                        codingFactory: codingFactory
                    )

                    self?.completeChunkCallSubmission(
                        encodedCall,
                        extrinsicService: extrinsicService,
                        submitting: submitting,
                        fileMetadata: fileMetadata
                    )
                } catch {
                    self?.failChunkCommit(for: submitting, error: error)
                }
            case let .failure(error):
                self?.failChunkCommit(for: submitting, error: error)
            }
        }
    }

    func completeChunkCallSubmission(
        _ encodedCall: Data,
        extrinsicService: ExtrinsicServiceProtocol,
        submitting: EvidenceSubmission.Progress.Submitting,
        fileMetadata: EvidenceSubmission.FileMetadata
    ) {
        do {
            guard let chain = chainRegistry.getChain(for: AppConfig.Chains.bulletInChain) else {
                return
            }
            let origin = try extrinsicOriginFactory.createSignedOrigin(
                for: wallet,
                chain: chain
            )

            let closure: ExtrinsicBuilderClosure = { builder in
                try builder.adding(rawCall: encodedCall)
            }

            extrinsicService.submit(
                closure,
                origin: origin,
                runningIn: syncQueue
            ) { [weak self] result in
                switch result {
                case let .success(model):
                    self?.logger.debug("Chunk submitted hash: \(model.txHash)")
                    self?.updateChunkSubmissionTxHash(model.txHash, mediaId: fileMetadata.mediaId)
                case let .failure(error):
                    self?.failChunkCommit(for: submitting, error: error)
                }
            }
        } catch {
            logger.error("Unexpected error: \(error)")

            failChunkCommit(for: submitting, error: error)
        }
    }

    func updateChunkSubmissionTxHash(_ txHash: String, mediaId: String) {
        guard case let .submitting(submitting) = session?.progress else {
            logger.warning("Can't set chunk submission tx hash as state changed")
            return
        }

        let newSubmitting = submitting.applingTxHash(txHash)

        let progress = EvidenceSubmission.Progress.submitting(newSubmitting)
        updateSession(progress: progress, mediaId: mediaId)
    }

    func failChunkCommit(for _: EvidenceSubmission.Progress.Submitting, error: Error) {
        logger.error("Chunk commit failed: \(error)")

        updateSession(error: .storeExtrinsic)
    }

    func completeEvidenceSubmission(
        with evidenceHash: Data,
        chunkSize: UInt64,
        mediaId: String,
        candidateType: PersonRegistration.CandidateType
    ) {
        guard let extrinsicFactory = getPeopleChainExtrinsicSubmissionFactory() else {
            logger.warning("People extrinsic service not ready")
            return
        }

        do {
            guard let chain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain) else {
                return
            }
            let origin = try extrinsicOriginFactory.createPersonRegistrationDefinition(
                for: candidateType,
                wallet: wallet,
                chain: chain
            )

            let evidenceHashHex = evidenceHash.toHex(includePrefix: true)
            logger.debug("Data submission completed. Submitting evidence hash \(evidenceHashHex)...")

            let completing = EvidenceSubmission.Progress.Completing(
                evidenceHash: evidenceHash,
                chunkSize: chunkSize,
                txHash: nil
            )
            let progress = EvidenceSubmission.Progress.completing(completing)
            updateSession(progress: progress, mediaId: mediaId)

            let call = ProofOfInkPallet.SubmitEvidenceCall(evidence: evidenceHash)

            let closure: ExtrinsicBuilderClosure = { builder in
                try builder.adding(call: call.runtimeCall())
            }

            let wrapper = extrinsicFactory.submitAndMonitorWrapper(
                extrinsicBuilderClosure: closure,
                origin: origin,
                params: .init(feeAssetId: nil, eventsMatcher: nil)
            )

            execute(
                wrapper: wrapper,
                inOperationQueue: operationQueue,
                runningCallbackIn: syncQueue
            ) { [weak self] result in
                do {
                    let executionResult = try result.get()

                    switch executionResult.status {
                    case let .success(extrinsic):
                        self?.updateEvidenceSubmissionTxHash(extrinsic.extrinsicHash, mediaId: mediaId)
                    case let .failure(extrinsic):
                        self?.failCompleteEvidenceSubmission(for: extrinsic.error)
                    }
                } catch {
                    self?.failCompleteEvidenceSubmission(for: error)
                }
            }
        } catch {
            logger.error("Unexpected error: \(error)")
            failCompleteEvidenceSubmission(for: error)
        }
    }

    func completeEvidenceSubmission(
        using fileMetadata: EvidenceSubmission.FileMetadata,
        chunkSize: UInt64,
        candidateType: PersonRegistration.CandidateType
    ) {
        do {
            guard let chunks = try? getChunks(for: fileMetadata, maxChunkSize: chunkSize),
                  let chunk = chunks.last else {
                updateSession(error: .chunksLoading)
                return
            }

            let evidenceHash = try chunk.blake2b32()
            completeEvidenceSubmission(
                with: evidenceHash,
                chunkSize: chunkSize,
                mediaId: fileMetadata.mediaId,
                candidateType: candidateType
            )
        } catch {
            failCompleteEvidenceSubmission(for: error)
        }
    }

    func updateEvidenceSubmissionTxHash(_ txHash: String, mediaId: String) {
        guard case let .completing(completing) = session?.progress else {
            logger.warning("Can't set evidence submission tx hash as state changed")
            return
        }

        let newCompleting = completing.applingTxHash(txHash)

        let progress = EvidenceSubmission.Progress.completing(newCompleting)
        updateSession(progress: progress, mediaId: mediaId)
    }

    func failCompleteEvidenceSubmission(for error: Error) {
        logger.error("Evidence hash submission failed: \(error)")

        updateSession(error: .submitHashExtrinsic)
    }

    func allocateFull(
        for mediaId: String,
        currentAuthorization: TransactionStoragePallet.Authorization?,
        candidateType: PersonRegistration.CandidateType
    ) {
        guard let submissionFactory = getPeopleChainExtrinsicSubmissionFactory() else {
            logger.warning("No submission factory found")
            return
        }

        do {
            guard let chain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain) else {
                return
            }
            let origin = try extrinsicOriginFactory.createPersonRegistrationDefinition(
                for: candidateType,
                wallet: wallet,
                chain: chain
            )

            let allocatingFull = EvidenceSubmission.Progress.AllocatingFull(
                txHash: nil,
                previousAllowedTransactions: currentAuthorization?.extent.transactions
            )

            let progress = EvidenceSubmission.Progress.allocatingFull(allocatingFull)
            updateSession(progress: progress, mediaId: mediaId)

            let call = ProofOfInkPallet.AllocateFull()

            let closure: ExtrinsicBuilderClosure = { builder in
                try builder.adding(call: call.runtimeCall())
            }

            let wrapper = submissionFactory.submitAndMonitorWrapper(
                extrinsicBuilderClosure: closure,
                origin: origin,
                params: .init(feeAssetId: nil, eventsMatcher: nil)
            )

            execute(
                wrapper: wrapper,
                inOperationQueue: operationQueue,
                runningCallbackIn: syncQueue
            ) { [weak self] result in
                do {
                    let executionResult = try result.get()

                    switch executionResult.status {
                    case let .success(extrinsic):
                        self?.updateAllocateFullTxHash(extrinsic.extrinsicHash, mediaId: mediaId)
                    case let .failure(extrinsic):
                        self?.failAllocateFull(for: extrinsic.error)
                    }
                } catch {
                    self?.failAllocateFull(for: error)
                }
            }
        } catch {
            logger.error("Unexpected error: \(error)")
            failAllocateFull(for: error)
        }
    }

    func updateAllocateFullTxHash(_ txHash: String, mediaId: String) {
        guard case let .allocatingFull(oldModel) = session?.progress else {
            logger.warning("Can't set allocate full tx hash as state changed")
            return
        }

        let allocatingFull = EvidenceSubmission.Progress.AllocatingFull(
            txHash: txHash,
            previousAllowedTransactions: oldModel.previousAllowedTransactions
        )

        let progress = EvidenceSubmission.Progress.allocatingFull(allocatingFull)
        updateSession(progress: progress, mediaId: mediaId)
    }

    func failAllocateFull(for error: Error) {
        logger.error("Allocate full failed: \(error)")

        updateSession(error: .allocateFull)
    }
}
