import AVFoundation
import UIKit

final class TattooEvidencePhotoInteractor {
    weak var presenter: TattooEvidencePhotoInteractorOutputProtocol?

    private let photoCaptureService: PhotoCaptureServiceProtocol
    private let fileManager: EvidenceFileManaging
    private let logger: LoggerProtocol

    init(
        photoCaptureService: PhotoCaptureServiceProtocol,
        fileManager: EvidenceFileManaging,
        logger: LoggerProtocol
    ) {
        self.photoCaptureService = photoCaptureService
        self.fileManager = fileManager
        self.logger = logger
    }
}

extension TattooEvidencePhotoInteractor: TattooEvidencePhotoInteractorInputProtocol {
    func setup() {
        photoCaptureService.checkAuthorizationAndSetupSession()
    }

    func capturePhoto() {
        do {
            let targetUrl = try fileManager.preparePhotoEvidenceUrl()
            MainActor.assumeIsolated {
                presenter?.didReceive(state: .capturing)
            }
            photoCaptureService.capturePhoto(withURL: targetUrl)
        } catch {
            MainActor.assumeIsolated {
                presenter?.didReceive(error: .storageError(error))
            }
        }
    }
}

extension TattooEvidencePhotoInteractor: CameraServiceDelegate {
    func didReceivedPhoto(_ photo: UIImage) {
        MainActor.assumeIsolated {
            presenter?.didReceive(state: .captured(photo))
        }
    }

    func didSetup(session: AVCaptureSession) {
        MainActor.assumeIsolated {
            presenter?.didReceive(session: session)
        }
    }

    func didSavePhoto(at url: URL) {
        logger.info("Did save photo to: \(url.absoluteString)")
        MainActor.assumeIsolated {
            presenter?.didSaveCapturedPhoto()
        }
    }

    func didFailToCapturePhoto(error: PhotoCaptureServiceError) {
        MainActor.assumeIsolated {
            presenter?.didReceive(error: .photoCapture(error))
        }
    }
}
