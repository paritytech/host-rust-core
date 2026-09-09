import Foundation

enum TattooCommitInteractorError: Error {
    case blockTimeServiceError(Error)
    case confirmationFailed(Error)
    case commitmentTimeout(Error)
    case judgementDuration(Error)
    case tattooMetadataFailed(Error)
    case commitAvailabilityFailed(Error)
}
