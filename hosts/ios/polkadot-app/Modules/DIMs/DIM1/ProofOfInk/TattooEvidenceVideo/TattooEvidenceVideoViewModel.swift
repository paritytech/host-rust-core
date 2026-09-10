import Foundation
import AVFoundation

enum TattooEvidenceVideoViewModel {
    case initial
    case sessionReady(AVCaptureSession?)
    case recording(progress: CGFloat, time: String)
    case processing(progress: CGFloat, time: String)
}
