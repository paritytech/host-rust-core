import Foundation
import AVFoundation

final class TattooEvidenceVideoInteractor {
    enum State: Equatable {
        case waitingSession
        case sessionInitialized
        case recording
        case completing
        case discarding
    }

    weak var presenter: TattooEvidVideoInteractorOutputProtocol?

    let videoCaptureService: VideoCaptureServiceProtocol
    let fileManager: EvidenceFileManaging
    private let stateMediator: ProvideEvidenceStateMediating
    private let idleStateMediator: ApplicationIdleStateMediating
    private(set) var state: State = .waitingSession

    private var recordings: [URL] = []

    init(
        videoCaptureService: VideoCaptureServiceProtocol,
        fileManager: EvidenceFileManaging,
        stateMediator: ProvideEvidenceStateMediating,
        idleStateMediator: ApplicationIdleStateMediating
    ) {
        self.videoCaptureService = videoCaptureService
        self.fileManager = fileManager
        self.stateMediator = stateMediator
        self.idleStateMediator = idleStateMediator
    }
}

extension TattooEvidenceVideoInteractor: TattooEvidVideoInteractorInputProtocol {
    func setup() {
        videoCaptureService.delegate = self
        videoCaptureService.startSession()
    }

    func start() {
        guard state == .sessionInitialized else {
            return
        }

        do {
            try stateMediator.clearExistingVideo()
            let videoUrl = try fileManager.generateVideoRecordingUrl()

            state = .recording

            recordings = [videoUrl]
            idleStateMediator.isIdleTimerDisabled = true
            videoCaptureService.startRecording(to: videoUrl)
        } catch {
            MainActor.assumeIsolated {
                presenter?.didReceive(error: .videoFile(error))
            }
        }
    }

    func discard() {
        guard state == .recording else {
            return
        }

        do {
            idleStateMediator.isIdleTimerDisabled = false
            videoCaptureService.stopRecording()
            try stateMediator.clearExistingVideo()
            recordings = []

            state = .discarding
        } catch {
            MainActor.assumeIsolated {
                presenter?.didReceive(error: .videoFile(error))
            }
        }
    }

    func complete() {
        guard state == .recording else {
            return
        }

        state = .completing
        idleStateMediator.isIdleTimerDisabled = false
        videoCaptureService.stopRecording()
    }
}

extension TattooEvidenceVideoInteractor: VideoCaptureServiceDelegate {
    func videoCaptureDidSetup(captureSession: AVCaptureSession) {
        state = .sessionInitialized

        MainActor.assumeIsolated {
            presenter?.didReceive(captureSession: captureSession)
        }
    }

    func videoCaptureDidCompleteRecording(file _: URL) {
        switch state {
        case .completing:
            state = .sessionInitialized
            MainActor.assumeIsolated {
                presenter?.didCompleteRecording(with: recordings)
            }

        case .discarding:
            state = .sessionInitialized

            do {
                try stateMediator.clearExistingVideo()
                MainActor.assumeIsolated {
                    presenter?.didDiscardRecording()
                }
            } catch {
                MainActor.assumeIsolated {
                    presenter?.didReceive(error: .videoFile(error))
                }
            }

        case .recording,
             .sessionInitialized,
             .waitingSession:
            break
        }
    }

    func videoCaptureDidFailure(error: VideoCaptureServiceError) {
        switch state {
        case .recording:
            state = .sessionInitialized
            videoCaptureService.stopRecording()
        case .completing,
             .discarding,
             .sessionInitialized,
             .waitingSession:
            break
        }

        MainActor.assumeIsolated {
            presenter?.didReceive(error: .videoCapture(error))
        }
    }
}
