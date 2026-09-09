import AVFoundation
import UIKit

protocol CameraSessionProtocol {
    var captureSession: AVCaptureSession { get }
    var isRunning: Bool { get }
    var sessionPreset: AVCaptureSession.Preset { get set }
    func beginConfiguration()
    func commitConfiguration()
    func canAddInput(_ input: AVCaptureInput) -> Bool
    func canAddOutput(_ output: AVCaptureOutput) -> Bool
    func addInput(_ input: AVCaptureInput)
    func addOutput(_ output: AVCaptureOutput)
    func startRunning()
    func stopRunning()
}

extension AVCaptureSession: CameraSessionProtocol {
    var captureSession: AVCaptureSession { self }
}

protocol CameraAuthorizationProtocol {
    static func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus
    static func requestAccess(for mediaType: AVMediaType, completionHandler: @Sendable @escaping (Bool) -> Void)
}

extension AVCaptureDevice: CameraAuthorizationProtocol {}
