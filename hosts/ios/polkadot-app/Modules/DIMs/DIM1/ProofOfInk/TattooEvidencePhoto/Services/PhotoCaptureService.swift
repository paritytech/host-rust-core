import AVFoundation
import Foundation
import UIKit

enum PhotoCaptureServiceError: Error {
    case userDeniedAccess
    case restrictedAccess
    case failedToInitializeInput
    case failedToAddInputOrOutput
    case failedToDecodePhoto
    case unknown(Error)
}

protocol PhotoCaptureServiceProtocol: AnyObject {
    func checkAuthorizationAndSetupSession()
    func capturePhoto(withURL url: URL)
}

protocol CameraServiceDelegate: AnyObject {
    func didSetup(session: AVCaptureSession)
    func didReceivedPhoto(_ photoPreview: UIImage)
    func didSavePhoto(at url: URL)
    func didFailToCapturePhoto(error: PhotoCaptureServiceError)
}

final class PhotoCaptureService: NSObject {
    private weak var delegate: CameraServiceDelegate!

    private var session: CameraSessionProtocol
    private var output: AVCapturePhotoOutput?
    private let photoCompressionService: PhotoCompressionServising
    private let authorization: CameraAuthorizationProtocol.Type
    private let dispatchQueue: DispatchQueue
    private let cameraQueue = DispatchQueue(label: "polkadot.app.photoCaptureService")

    private var currentPhotoURL: URL!

    init(
        session: CameraSessionProtocol = AVCaptureSession(),
        photoCompressionService: PhotoCompressionServising = PhotoCompressionService(),
        dispatchQueue: DispatchQueue = DispatchQueue.main,
        authorization: CameraAuthorizationProtocol.Type = AVCaptureDevice.self
    ) {
        self.session = session
        self.photoCompressionService = photoCompressionService
        self.dispatchQueue = dispatchQueue
        self.authorization = authorization
        super.init()
    }

    func use(delegate: CameraServiceDelegate) {
        self.delegate = delegate
    }
}

extension PhotoCaptureService: PhotoCaptureServiceProtocol {
    func checkAuthorizationAndSetupSession() {
        switch authorization.authorizationStatus(for: .video) {
        case .authorized:
            startSessionSetup()
        case .notDetermined:
            authorization.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.startSessionSetup()
                } else {
                    self?.notifyDelegate(with: .userDeniedAccess)
                }
            }
        default:
            notifyDelegate(with: .restrictedAccess)
        }
    }

    func capturePhoto(withURL url: URL) {
        let settings = photoSettings()
        cameraQueue.async { [weak self] in
            guard let self else { return }
            currentPhotoURL = url
            output?.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension PhotoCaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            notifyDelegate(with: .unknown(error))
        } else {
            if let data = photo.fileDataRepresentation(), let preview = UIImage(data: data) {
                dispatchQueue.async {
                    self.delegate.didReceivedPhoto(preview)
                }
            }
            cameraQueue.async { [weak self] in
                guard let self else { return }
                save(photo: photo, to: currentPhotoURL)
            }
        }
    }
}

private extension PhotoCaptureService {
    func photoSettings() -> AVCapturePhotoSettings {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.flashMode = .auto
        photoSettings.photoQualityPrioritization = .balanced
        return photoSettings
    }

    func notifyDelegate(with error: PhotoCaptureServiceError) {
        dispatchQueue.async {
            self.delegate.didFailToCapturePhoto(error: error)
        }
    }

    func startSessionSetup() {
        cameraQueue.async { self.setupSession() }
    }

    func setupSession() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            notifyDelegate(with: .failedToInitializeInput)
            return
        }
        let output = AVCapturePhotoOutput()
        self.output = output
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.photo
        if session.canAddInput(input), session.canAddOutput(output) {
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
        } else {
            notifyDelegate(with: .failedToAddInputOrOutput)
        }
        session.startRunning()
        dispatchQueue.async {
            self.delegate.didSetup(session: self.session.captureSession)
        }
    }

    func save(photo: AVCapturePhoto, to url: URL) {
        guard
            let compressedData = photoCompressionService.compressPhoto(photo),
            UIImage(data: compressedData) != nil
        else {
            notifyDelegate(with: .failedToDecodePhoto)
            return
        }
        do {
            try compressedData.write(to: url, options: .atomic)
            dispatchQueue.async {
                self.delegate.didSavePhoto(at: url)
            }
        } catch {
            notifyDelegate(with: .unknown(error))
        }
    }
}
