import BulletinChain
import Foundation
import SubstrateSdk
import Individuality

enum EvidenceSubmission {
    struct RemoteState: Equatable {
        let candidate: ProofOfInkPallet.Candidate?
        let transactionStorageAuthorizations: TransactionStoragePallet.Authorization?
        let bulletInBlockNumber: BlockNumber?

        func applyingPeopleChange(from change: PersonhoodRegistrationSyncChange) -> RemoteState {
            .init(
                candidate: change.proofOfInkCandidate.valueWhenDefined(else: candidate),
                transactionStorageAuthorizations: transactionStorageAuthorizations,
                bulletInBlockNumber: bulletInBlockNumber
            )
        }

        func applyingBulletInChange(from change: TattooUploadingBulletInSyncChange) -> RemoteState {
            .init(
                candidate: candidate,
                transactionStorageAuthorizations: change.authorizations.valueWhenDefined(
                    else: transactionStorageAuthorizations
                ),
                bulletInBlockNumber: change.blockNumber.value ?? bulletInBlockNumber
            )
        }
    }

    struct RemoteConstants {
        let authorizationPeriod: UInt32
    }

    struct ChunksInfo: Codable {
        let chunks: [String]
        let hash: String
        let totalSize: Int
        let path: String
    }

    struct FileMetadata: Equatable {
        let fileUrl: URL
        let allocation: ProofOfInkPallet.Allocation
        let mediaId: String

        init(fileUrl: URL, allocation: ProofOfInkPallet.Allocation, mediaId: String) {
            self.fileUrl = fileUrl
            self.allocation = allocation
            self.mediaId = mediaId
        }

        init?(baseUrl: URL, name: String, allocation: ProofOfInkPallet.Allocation, mediaId: String) {
            guard let url = (baseUrl as NSURL).appendingPathComponent(name) else {
                return nil
            }

            self.init(fileUrl: url, allocation: allocation, mediaId: mediaId)
        }
    }

    struct File {
        let chunks: [Data]
        let metadata: FileMetadata
    }

    struct LocalState: Equatable, Codable {
        let videoName: String
        let photoName: String
        let sessionId: String

        var videoId: String {
            "video-\(sessionId)"
        }

        var photoId: String {
            "photo-\(sessionId)"
        }
    }

    struct Session: Codable {
        enum Error: Codable {
            case storeExtrinsic
            case submitHashExtrinsic
            case mediaMismatch
            case chunksLoading
            case allocateFull
            case notEnoughStorage
            case storageExpired
        }

        let identifier: String
        let mediaId: String?
        let progress: Progress?
        let error: Error?

        init(identifier: String, mediaId: String? = nil, progress: Progress? = nil, error: Error? = nil) {
            self.identifier = identifier
            self.mediaId = mediaId
            self.progress = progress
            self.error = error
        }
    }

    enum Progress: Codable {
        struct Submitting: Codable {
            let chunkSize: UInt64
            let chunkIndex: Int
            let totalChunks: Int
            let remoteRemainedBefore: UInt64
            let txHash: String?

            var isLastChunk: Bool {
                chunkIndex == totalChunks - 1
            }

            func checkCommitment(for newAuthorization: TransactionStoragePallet.Authorization) -> Bool {
                newAuthorization.extent.bytes + UInt64(chunkSize) <= remoteRemainedBefore
            }

            func applingTxHash(_ txHash: String?) -> Submitting {
                .init(
                    chunkSize: chunkSize,
                    chunkIndex: chunkIndex,
                    totalChunks: totalChunks,
                    remoteRemainedBefore: remoteRemainedBefore,
                    txHash: txHash
                )
            }
        }

        struct Completing: Codable {
            let evidenceHash: Data
            let chunkSize: UInt64
            let txHash: String?

            func applingTxHash(_ txHash: String?) -> Completing {
                .init(
                    evidenceHash: evidenceHash,
                    chunkSize: chunkSize,
                    txHash: txHash
                )
            }
        }

        struct AllocatingFull: Codable {
            let txHash: String?
            let previousAllowedTransactions: UInt32?
        }

        case waiting
        case submitting(Submitting)
        case completing(Completing)
        case allocatingFull(AllocatingFull)

        func checkCanSubmitChunk(resubmittingIfNoHash: Bool) -> Bool {
            switch self {
            case let .submitting(submitting):
                submitting.txHash == nil && resubmittingIfNoHash
            case .waiting,
                 .completing,
                 .allocatingFull:
                true
            }
        }

        func checkCanAllocateFull(resubmittingIfNoHash: Bool) -> Bool {
            switch self {
            case let .allocatingFull(allocating):
                allocating.txHash == nil && resubmittingIfNoHash
            case .submitting,
                 .completing,
                 .waiting:
                true
            }
        }

        func checkCanCompleteEvidenceSubmission(resubmittingIfNoHash: Bool) -> Bool {
            switch self {
            case let .completing(completing):
                completing.txHash == nil && resubmittingIfNoHash
            case .waiting,
                 .submitting,
                 .allocatingFull:
                true
            }
        }
    }
}

extension EvidenceSubmission.RemoteState {
    static var empty: EvidenceSubmission.RemoteState {
        .init(candidate: nil, transactionStorageAuthorizations: nil, bulletInBlockNumber: nil)
    }
}

extension EvidenceSubmission.Session {
    func changingMediaId(_ newMediaId: String) -> Self {
        .init(
            identifier: identifier,
            mediaId: newMediaId,
            progress: progress,
            error: error
        )
    }

    func changingError(_ newError: EvidenceSubmission.Session.Error?) -> Self {
        .init(
            identifier: identifier,
            mediaId: mediaId,
            progress: progress,
            error: newError
        )
    }

    func changingProgress(_ newProgress: EvidenceSubmission.Progress?) -> Self {
        .init(
            identifier: identifier,
            mediaId: mediaId,
            progress: newProgress,
            error: error
        )
    }

    func clearingTxHash() -> Self {
        switch progress {
        case let .submitting(submitting):
            let newProgress = EvidenceSubmission.Progress.submitting(submitting.applingTxHash(nil))
            return changingProgress(newProgress)
        case let .allocatingFull(allocatingFull):
            let newProgress = EvidenceSubmission.Progress.allocatingFull(
                .init(
                    txHash: nil,
                    previousAllowedTransactions: allocatingFull.previousAllowedTransactions
                )
            )
            return changingProgress(newProgress)
        case let .completing(completing):
            let newProgress = EvidenceSubmission.Progress.completing(completing.applingTxHash(nil))
            return changingProgress(newProgress)
        case .waiting,
             .none:
            return self
        }
    }
}
