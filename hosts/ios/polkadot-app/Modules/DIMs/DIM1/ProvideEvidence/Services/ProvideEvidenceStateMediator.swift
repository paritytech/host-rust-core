import Foundation
import AsyncExtensions
import AsyncAlgorithms

enum ProvideEvidenceState: Equatable {
    case noEvidence
    case existingVideo(recordings: [URL])
    case confirmedVideo
}

protocol ProvideEvidenceStateMediating: AnyObject {
    func state() -> ProvideEvidenceState
    func stateStream() -> AnyAsyncSequence<ProvideEvidenceState>
    func confirmVideo()
    func clearExistingVideo() throws
}

final class ProvideEvidenceStateMediator {
    private let fileManager: EvidenceFileManaging
    private let videoFrameService: VideoFrameServicing
    private let defaultsStorage: DefaultsStoring

    init(
        fileManager: EvidenceFileManaging,
        videoFrameService: VideoFrameServicing = VideoFrameService(),
        defaultsStorage: DefaultsStoring = UserDefaults.standard
    ) {
        self.fileManager = fileManager
        self.videoFrameService = videoFrameService
        self.defaultsStorage = defaultsStorage
    }
}

extension ProvideEvidenceStateMediator: ProvideEvidenceStateMediating {
    func state() -> ProvideEvidenceState {
        do {
            // check if media is not damaged
            let videoUrl = try fileManager.prepareVideoExport()
            _ = try videoFrameService.getFrame(at: 0, from: videoUrl)
        } catch {
            return .noEvidence
        }

        let existingRecordings: [URL] = (try? fileManager.existingVideoRecordings()) ?? []
        if !existingRecordings.isEmpty {
            if defaultsStorage[bool: .isVideoConfirmed] {
                return .confirmedVideo
            }
            return .existingVideo(recordings: existingRecordings)
        }

        return .noEvidence
    }

    // TODO: Consider better implementation
    func stateStream() -> AnyAsyncSequence<ProvideEvidenceState> {
        provideEvidenceStatePollingStream(interval: .seconds(0.5))
    }

    func confirmVideo() {
        defaultsStorage[bool: .isVideoConfirmed] = true
    }

    func clearExistingVideo() throws {
        defaultsStorage[bool: .isVideoConfirmed] = false
        try fileManager.forgetVideoEvidence()
    }
}

private extension ProvideEvidenceStateMediator {
    func provideEvidenceStatePollingStream(
        interval: Duration
    ) -> AnyAsyncSequence<ProvideEvidenceState> {
        AsyncStream<ProvideEvidenceState> { [weak self] continuation in
            let task = Task {
                while !Task.isCancelled {
                    guard let self else {
                        continuation.finish()
                        break
                    }
                    continuation.yield(self.state())

                    try await Task.sleep(for: interval)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        .removeDuplicates()
        .eraseToAnyAsyncSequence()
    }
}
