import Foundation

enum TattooVideoPreviewInteractorError: Error {
    case videoExport(Error)
    case videoFile(Error)
}
