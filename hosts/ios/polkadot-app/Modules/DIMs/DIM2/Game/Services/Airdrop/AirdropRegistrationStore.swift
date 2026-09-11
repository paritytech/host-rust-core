import Foundation
import SubstrateSdk
import Operation_iOS
import StructuredConcurrency

/// The claim-relevant outcome of an airdrop registration, persisted at sign-up time so that the
/// later claim uses the exact same method/beneficiary that was registered — rather than re-deriving
/// it from state that may have drifted (recognition, source) by the time the prize is claimed.
struct AirdropRegistrationRecord: Equatable {
    let gameIndex: UInt32
    let beneficiary: AccountId
    /// `true` when registered via the Alias (recognized person) variant — claim must sign with the
    /// person/score-alias origin; `false` for the Account variant (candidate origin).
    let usesScoreAlias: Bool
}

extension AirdropRegistrationRecord: Identifiable {
    var identifier: String { String(gameIndex) }
}

protocol AirdropRegistrationStoring {
    func save(_ record: AirdropRegistrationRecord) async throws
    func record(forGameIndex gameIndex: UInt32) async throws -> AirdropRegistrationRecord?
}

final class AirdropRegistrationStore: AirdropRegistrationStoring {
    private let repository: AnyDataProviderRepository<AirdropRegistrationRecord>

    init(storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared) {
        repository = AnyDataProviderRepository(
            storageFacade.createRepository(mapper: AnyCoreDataMapper(AirdropRegistrationMapper()))
        )
    }

    func save(_ record: AirdropRegistrationRecord) async throws {
        try await repository.saveOperation({ [record] }, { [] }).asyncExecute()
    }

    func record(forGameIndex gameIndex: UInt32) async throws -> AirdropRegistrationRecord? {
        let operation = repository.fetchOperation(
            by: { String(gameIndex) },
            options: RepositoryFetchOptions()
        )
        return try await operation.asyncExecute()
    }
}
