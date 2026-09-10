import Foundation
import AVFoundation
import Foundation_iOS

@MainActor
final class TattooEvidenceVideoPresenter {
    weak var view: TattooEvidenceVideoViewProtocol?
    let wireframe: TattooEvidenceVideoWireframeProtocol
    let interactor: TattooEvidVideoInteractorInputProtocol

    let logger: LoggerProtocol
    let maxVideoLength: TimeInterval
    let minVideoLength: TimeInterval

    private var timer: CountdownTimerProtocol?
    private var recordedDuration: TimeInterval?

    init(
        interactor: TattooEvidVideoInteractorInputProtocol,
        wireframe: TattooEvidenceVideoWireframeProtocol,
        maxVideoLength: TimeInterval = UInt64(3).minutesToSeconds(),
        minVideoLength: TimeInterval = 1.5 * TimeInterval.secondsInMinute,
        logger: LoggerProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.maxVideoLength = maxVideoLength
        self.minVideoLength = minVideoLength
        self.logger = logger
    }

    private func setupTimerIfNeeded() {
        guard timer == nil else {
            return
        }

        timer = CountdownTimer()
        timer?.delegate = self
    }

    private func runTimer() {
        setupTimerIfNeeded()

        timer?.start(with: maxVideoLength)
    }

    private func stopTimer() -> TimeInterval {
        let optRemainedTime = timer?.remainedInterval

        timer?.delegate = nil
        timer?.stop()
        timer = nil

        if let remainedTime = optRemainedTime {
            return maxVideoLength - remainedTime
        } else {
            return 0
        }
    }

    private func provideInProgressViewModel(for remainedInterval: TimeInterval) {
        let progressInSeconds = max(maxVideoLength - remainedInterval, 0)

        let time = progressInSeconds.localizedMinuteSeconds(for: selectedLocale)
        let progress = progressInSeconds / maxVideoLength

        view?.didReceive(viewModel: .recording(progress: progress, time: time ?? ""))
    }

    private func provideProcessingViewModel(for recordedInterval: TimeInterval) {
        let time = recordedInterval.localizedMinuteSeconds(for: selectedLocale)
        let progress = recordedInterval / maxVideoLength

        view?.didReceive(viewModel: .processing(progress: progress, time: time ?? ""))
    }
}

extension TattooEvidenceVideoPresenter: TattooEvidenceVideoPresenterProtocol {
    func setup() {
        view?.didReceive(viewModel: .initial)

        interactor.setup()
    }

    func toggleRecording() {
        switch timer?.state {
        case .paused,
             .stopped,
             .none:
            runTimer()
            recordedDuration = nil
            provideInProgressViewModel(for: maxVideoLength)

            interactor.start()
        case .inProgress:
            let recordedDuration = stopTimer()
            self.recordedDuration = recordedDuration

            provideProcessingViewModel(for: recordedDuration)

            if recordedDuration >= minVideoLength {
                interactor.complete()
            } else {
                interactor.discard()
            }
        }
    }

    func openTips() {
        wireframe.showTips(from: view)
    }
}

extension TattooEvidenceVideoPresenter: TattooEvidVideoInteractorOutputProtocol {
    func didCompleteRecording(with urls: [URL]) {
        recordedDuration = nil
        view?.didReceive(viewModel: .sessionReady(nil))
        logger.debug("Did complete recording")

        wireframe.showPreview(from: view, recordings: urls)
    }

    func didReceive(captureSession: AVCaptureSession) {
        view?.didReceive(viewModel: .sessionReady(captureSession))
    }

    func didDiscardRecording() {
        recordedDuration = nil
        view?.didReceive(viewModel: .sessionReady(nil))

        logger.debug("Did complete discard")
    }

    func didReceive(error: TattooEvidVideoInteractorError) {
        logger.error("Did receive error: \(error)")

        _ = stopTimer()
        recordedDuration = nil

        switch error {
        case let .videoCapture(videoCaptureError):
            processVideoCapture(error: videoCaptureError)
        case .videoFile:
            view?.didReceive(viewModel: .sessionReady(nil))
            _ = wireframe.present(error: error, from: view)
        }
    }

    private func processVideoCapture(error: VideoCaptureServiceError) {
        switch error {
        case .deviceAccessDeniedPreviously,
             .deviceAccessDeniedNow,
             .deviceAccessRestricted:
            view?.didReceive(viewModel: .initial)

            wireframe.askOpenApplicationSettings(
                with: String(localized: .Tattoo.cameraNotAllowedMessage),
                title: String(localized: .Tattoo.cameraNotAllowedTitle),
                from: view
            )
        case .sessionNotRunning:
            view?.didReceive(viewModel: .initial)
            _ = wireframe.present(error: error, from: view)
        case let .internalError(error):
            view?.didReceive(viewModel: .sessionReady(nil))
            _ = wireframe.present(error: error, from: view)
        }
    }
}

extension TattooEvidenceVideoPresenter: @MainActor CountdownTimerDelegate {
    func didStart(with remainedInterval: TimeInterval) {
        provideInProgressViewModel(for: remainedInterval)
    }

    func didCountdown(remainedInterval: TimeInterval) {
        provideInProgressViewModel(for: remainedInterval)
    }

    func didStop(with remainedInterval: TimeInterval) {
        if remainedInterval <= 0 {
            provideProcessingViewModel(for: maxVideoLength)
            recordedDuration = maxVideoLength
            timer = nil

            interactor.complete()
        }
    }
}

extension TattooEvidenceVideoPresenter: @MainActor Localizable {
    func applyLocalization() {
        if let remainedTimeInterval = timer?.remainedInterval {
            provideInProgressViewModel(for: remainedTimeInterval)
        } else if let recordedDuration {
            provideProcessingViewModel(for: recordedDuration)
        }
    }
}
