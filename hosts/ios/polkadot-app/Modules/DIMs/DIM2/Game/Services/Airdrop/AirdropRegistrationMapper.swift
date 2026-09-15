import CoreData
import Foundation
import Operation_iOS
import SubstrateSdk

final class AirdropRegistrationMapper: CoreDataMapperProtocol {
    var entityIdentifierFieldName: String { #keyPath(CDAirdropRegistration.identifier) }

    typealias DataProviderModel = AirdropRegistrationRecord
    typealias CoreDataEntity = CDAirdropRegistration

    func transform(entity: CDAirdropRegistration) throws -> AirdropRegistrationRecord {
        guard let beneficiary = entity.beneficiary else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDAirdropRegistration.beneficiary))
        }

        return AirdropRegistrationRecord(
            gameIndex: UInt32(entity.gameIndex),
            beneficiary: beneficiary,
            usesScoreAlias: entity.usesScoreAlias
        )
    }

    func populate(
        entity: CDAirdropRegistration,
        from model: AirdropRegistrationRecord,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.gameIndex = Int64(model.gameIndex)
        entity.beneficiary = model.beneficiary
        entity.usesScoreAlias = model.usesScoreAlias
    }
}
