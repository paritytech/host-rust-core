import Foundation
import os
import StructuredConcurrency

final class ClaimFullUsernameInteractor {
    weak var presenter: ClaimUsernameInteractorOutputProtocol?

    private let registeredData: People.RegisteredData
    private let claimService: FullUsernameClaimServicing
    private let availabilityValidator: FullUsernameAvailabilityValidating
    private let usernameStorage: UsernameStoring
    private let logger: LoggerProtocol

    private let availability = OSAllocatedUnfairLock<FullUsernameAvailability?>(initialState: nil)

    init(
        registeredData: People.RegisteredData,
        claimService: FullUsernameClaimServicing,
        availabilityValidator: FullUsernameAvailabilityValidating = FullUsernameAvailabilityValidator(),
        usernameStorage: UsernameStoring = UsernameStorage(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.registeredData = registeredData
        self.claimService = claimService
        self.availabilityValidator = availabilityValidator
        self.usernameStorage = usernameStorage
        self.logger = logger
    }
}

extension ClaimFullUsernameInteractor: ClaimUsernameInteractorInputProtocol {
    var metadata: UsernameMetadata {
        .default
    }

    func claim(username: Username) async throws -> Username {
        guard let availability = availability.withLock({ $0 }) else {
            logger.error("Missing availability")
            throw InteractorError.missingAvailability
        }

        try await claimService.claimUsername(username, with: availability)
        return username
    }

    func check(username: Username) async throws -> UsernameAvailableType {
        try await withMinDuration(.milliseconds(300)) {
            let value = try await availabilityValidator.checkAvailability(for: username)
            updateAvailability(value)
            return value.toAvailableType
        }
    }

    func save(username: Username) async {
        usernameStorage.username = username
        await presenter?.didSaveUsername()
    }
}

private extension ClaimFullUsernameInteractor {
    enum InteractorError: Error {
        case missingAvailability
    }

    func updateAvailability(_ availability: FullUsernameAvailability) {
        self.availability.withLock { $0 = availability }
    }
}

private extension FullUsernameAvailability {
    var toAvailableType: UsernameAvailableType {
        switch self {
        case .free,
             .reservedByUs,
             .reclaimExpiredReservation:
            .available(digits: [])
        case .notAvailable:
            .taken
        }
    }
}
