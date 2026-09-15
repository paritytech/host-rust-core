import Foundation
import Operation_iOS

protocol InvitationStorageServiceProtocol {
    func fetchInvitation(
        of type: Invitation.InvitationType
    ) async throws -> Invitation?
    func saveInvitation(
        of type: Invitation.InvitationType,
        from response: IssueInvitationResponse
    ) async throws -> Invitation
    func removeInvitation(
        of type: Invitation.InvitationType
    ) async throws
}

final class InvitationStorageService {
    private let repositoryFactory: InvitationRepositoryFactoryProtocol

    init(
        repositoryFactory: InvitationRepositoryFactoryProtocol = InvitationRepositoryFactory()
    ) {
        self.repositoryFactory = repositoryFactory
    }
}

extension InvitationStorageService: InvitationStorageServiceProtocol {
    func fetchInvitation(
        of type: Invitation.InvitationType
    ) async throws -> Invitation? {
        let repository = repositoryFactory.createInvitationRepository()
        return try await repository.fetchOperation(by: { type.rawValue }, options: .init()).asyncExecute()
    }

    func saveInvitation(
        of type: Invitation.InvitationType,
        from response: IssueInvitationResponse
    ) async throws -> Invitation {
        let invitation = Invitation(
            type: type,
            owner: response.claimedBy,
            issuer: response.inviter,
            publicKey: response.publicKey,
            signature: response.signature
        )
        let repository = repositoryFactory.createInvitationRepository()
        let saveOperation = repository.saveOperation({ [invitation] }, { [] })

        try await CompoundOperationWrapper(targetOperation: saveOperation).asyncExecute()

        return invitation
    }

    func removeInvitation(
        of type: Invitation.InvitationType
    ) async throws {
        let repository = repositoryFactory.createInvitationRepository()
        let operation = repository.saveOperation({ [] }, { [type.rawValue] })
        try await operation.asyncExecute()
    }
}
