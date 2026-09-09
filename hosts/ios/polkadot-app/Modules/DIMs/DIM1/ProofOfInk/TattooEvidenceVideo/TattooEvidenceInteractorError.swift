import Foundation
import UIKitExt

enum TattooEvidVideoInteractorError: Error {
    case videoCapture(VideoCaptureServiceError)
    case videoFile(Error)
}

extension TattooEvidVideoInteractorError: ErrorContentConvertible {
    func toErrorContent() -> ErrorContent {
        switch self {
        case .videoCapture:
            ErrorContent(
                title: String(localized: .Common.error),
                message: String(localized: .Tattoo.evidenceVideoRecorderError)
            )
        case .videoFile:
            ErrorContent(
                title: String(localized: .Common.error),
                message: String(localized: .Tattoo.evidenceVideoFileError)
            )
        }
    }
}
