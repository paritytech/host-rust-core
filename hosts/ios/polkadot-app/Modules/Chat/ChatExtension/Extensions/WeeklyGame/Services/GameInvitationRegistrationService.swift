import Foundation
import Operation_iOS
import StructuredConcurrency
import Individuality

protocol GameInvitationRegistering {
    func register(airdrop: GamePallet.AirdropVrfs?) async throws
}

enum GameInvitationRegistrationError: Error {
    case pendingInviteTimedOut
}

final class GameInvitationRegistrationService {
    private let invitationFactory: InvitationIssuanceServicing
    private let invitationStorage: InvitationStorageServiceProtocol
    private let observerFactory: PendingInvitationObserverMaking
    private let gameRegisterService: GameRegisterServicing
    private let pendingTimeout: TimeInterval
    private let logger: LoggerProtocol

    init(
        invitationFactory: InvitationIssuanceServicing,
        invitationStorage: InvitationStorageServiceProtocol,
        observerFactory: PendingInvitationObserverMaking,
        gameRegisterService: GameRegisterServicing,
        pendingTimeout: TimeInterval = 15,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.invitationFactory = invitationFactory
        self.invitationStorage = invitationStorage
        self.observerFactory = observerFactory
        self.gameRegisterService = gameRegisterService
        self.pendingTimeout = pendingTimeout
        self.logger = logger
    }
}

extension GameInvitationRegistrationService: GameInvitationRegistering {
    func register(airdrop: GamePallet.AirdropVrfs?) async throws {
        let invitation = try await ensureInvitation()
        try await markStallRegion("Check invitation") {
            try await waitPendingOnChain(invitation: invitation)
        }
        try await markStallRegion("Submit registration") {
            try await submitRegistration(invitation: invitation, airdrop: airdrop)
            await removeInvitation()
        }
    }
}

private extension GameInvitationRegistrationService {
    func ensureInvitation() async throws -> Invitation {
        if let stored = try await invitationStorage.fetchInvitation(of: .game) {
            logger.debug("Reusing stored invitation")
            return stored
        }

        let response = try await invitationFactory.issueInvitation(type: .game)
        let invitation = try await invitationStorage.saveInvitation(of: .game, from: response)
        logger.debug("Issued and persisted new invitation")

        return invitation
    }

    func waitPendingOnChain(invitation: Invitation) async throws {
        do {
            try await performWaitPendingOnChain(invitation: invitation)
        } catch {
            logger.warning("No invitation on chain, assuming unexpected behavior, removing invitation from db")
            await removeInvitation()
            throw error
        }
    }

    func performWaitPendingOnChain(invitation: Invitation) async throws {
        let observer = observerFactory.makeObserver(
            ticketPublicKey: invitation.publicKey,
            issuer: invitation.issuer,
            of: .game
        )
        observer.setup()
        defer { observer.throttle() }

        do {
            try await withTimeout(.seconds(pendingTimeout)) {
                for try await state in observer.observe() where state == true {
                    return
                }
            }
        } catch is TimeoutError {
            throw GameInvitationRegistrationError.pendingInviteTimedOut
        }
    }

    func submitRegistration(invitation: Invitation, airdrop: GamePallet.AirdropVrfs?) async throws {
        let result = try await gameRegisterService
            .registerForGame(with: invitation, airdrop: airdrop)
            .asyncExecute()

        switch result.status {
        case .success:
            return
        case let .failure(failedExtrinsic):
            throw failedExtrinsic.error
        }
    }

    func removeInvitation() async {
        do {
            try await invitationStorage.removeInvitation(of: .game)
            logger.debug("Did remove used invitation")
        } catch {
            logger.error("Failed to remove invitation: \(error)")
        }
    }
}
