import Foundation
import Operation_iOS
import CoreData
import SubstrateSdk

struct BannedPlayer: Identifiable, Equatable {
    let accountId: AccountId

    var identifier: String { accountId.toHex() }
}

final class BannedPlayerMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = BannedPlayer
    typealias CoreDataEntity = CDBannedPlayer

    var entityIdentifierFieldName: String { #keyPath(CDBannedPlayer.accountId) }

    func populate(
        entity: CDBannedPlayer,
        from model: BannedPlayer,
        using _: NSManagedObjectContext
    ) throws {
        entity.accountId = model.accountId.toHex()
    }

    func transform(entity: CDBannedPlayer) throws -> BannedPlayer {
        guard let hex = entity.accountId else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CDBannedPlayer.accountId)
            )
        }
        return try BannedPlayer(accountId: hex.fromHex())
    }
}
