import Foundation
import AVFoundation
import Operation_iOS

protocol VideoCaptureServiceProtocol: AnyObject {
    var delegate: VideoCaptureServiceDelegate? { get set }

    func startSession()
    func startRecording(to outputUrl: URL)
    func stopRecording()
    func stopSession()
}

enum VideoCaptureServiceError: Error {
    case deviceAccessDeniedPreviously
    case deviceAccessDeniedNow
    case deviceAccessRestricted
    case sessionNotRunning
    case internalError(Error)
}

protocol VideoCaptureServiceDelegate: AnyObject {
    func videoCaptureDidSetup(captureSession: AVCaptureSession)
    func videoCaptureDidCompleteRecording(file: URL)
    func videoCaptureDidFailure(error: VideoCaptureServiceError)
}

final class VideoCaptureService: NSObject {
    static let processingQueue = DispatchQueue(label: "polkadot.app.video.capture.service.queue")

    private(set) var captureSession: AVCaptureSession?
    private(set) var movieOutput: AVCaptureMovieFileOutput?

    weak var delegate: VideoCaptureServiceDelegate?
    let delegateQueue: DispatchQueue

    init(
        delegate: VideoCaptureServiceDelegate?,
        delegateQueue: DispatchQueue = .main
    ) {
        self.delegate = delegate
        self.delegateQueue = delegateQueue

        super.init()
    }

    private func configureSessionIfNeeded() throws {
        guard self.captureSession == nil else {
            return
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        let device = discoverySession.devices.first

        guard let camera = device else {
            throw VideoCaptureServiceError.deviceAccessRestricted
        }

        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            throw VideoCaptureServiceError.deviceAccessRestricted
        }

        let output = AVCaptureMovieFileOutput()

        let captureSession = AVCaptureSession()

        guard captureSession.canAddInput(input), captureSession.canAddOutput(output) else {
            throw VideoCaptureServiceError.deviceAccessRestricted
        }

        captureSession.addInput(input)
        captureSession.addOutput(output)

        if let connection = output.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }

        movieOutput = output
        self.captureSession = captureSession
    }

    private func startAuthorizedSession() {
        dispatchInQueueWhenPossible(VideoCaptureService.processingQueue) {
            do {
                try self.configureSessionIfNeeded()

                if let captureSession = self.captureSession {
                    captureSession.startRunning()

                    self.notifyDelegateWithCreation(of: captureSession)
                }
            } catch {
                self.notifyDelegate(with: .internalError(error))
            }
        }
    }

    private func notifyDelegate(with error: VideoCaptureServiceError) {
        dispatchInQueueWhenPossible(delegateQueue) {
            self.delegate?.videoCaptureDidFailure(error: error)
        }
    }

    private func notifyDelegateWithCreation(of captureSession: AVCaptureSession) {
        dispatchInQueueWhenPossible(delegateQueue) {
            self.delegate?.videoCaptureDidSetup(captureSession: captureSession)
        }
    }
}

extension VideoCaptureService: VideoCaptureServiceProtocol {
    func startSession() {
        guard captureSession == nil else {
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startAuthorizedSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.startAuthorizedSession()
                } else {
                    self.notifyDelegate(with: .deviceAccessDeniedNow)
                }
            }
        case .denied:
            notifyDelegate(with: .deviceAccessDeniedPreviously)
        case .restricted:
            notifyDelegate(with: .deviceAccessRestricted)
        @unknown default:
            break
        }
    }

    func startRecording(to outputUrl: URL) {
        guard captureSession != nil else {
            return
        }

        dispatchInQueueWhenPossible(VideoCaptureService.processingQueue) {
            self.movieOutput?.startRecording(to: outputUrl, recordingDelegate: self)
        }
    }

    func stopRecording() {
        guard captureSession != nil else {
            return
        }

        dispatchInQueueWhenPossible(VideoCaptureService.processingQueue) {
            self.movieOutput?.stopRecording()
        }
    }

    func stopSession() {
        guard captureSession != nil else {
            return
        }

        dispatchInQueueWhenPossible(VideoCaptureService.processingQueue) {
            if let movieOutput = self.movieOutput, movieOutput.isRecording {
                movieOutput.stopRecording()
            }

            self.captureSession?.stopRunning()
        }
    }
}

extension VideoCaptureService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        if let error {
            notifyDelegate(with: .internalError(error))
        }

        dispatchInQueueWhenPossible(delegateQueue) {
            self.delegate?.videoCaptureDidCompleteRecording(file: outputFileURL)
        }
    }
}
