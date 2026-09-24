import CoreData
import Operation_iOS
import Products

/// The newest face held for a card, as the text the renderer decoder reads.
/// Kept apart from membership so a host-placed card, which has no membership
/// row, still keeps the face its product last drew.
struct StoredPocketCardFace: Identifiable, Equatable {
    let key: PocketCardKey
    let faceJson: String

    var identifier: String { key.storageId }
    var id: String { identifier }
}

final class PocketCardFaceMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = StoredPocketCardFace
    typealias CoreDataEntity = CDPocketCardFace
}

extension PocketCardFaceMapper: CoreDataMapperProtocol {
    func transform(entity: CDPocketCardFace) throws -> StoredPocketCardFace {
        guard let productId = entity.productId else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDPocketCardFace.productId))
        }

        guard let cardId = entity.cardId else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDPocketCardFace.cardId))
        }

        guard let faceJson = entity.faceJson else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDPocketCardFace.faceJson))
        }

        return StoredPocketCardFace(
            key: PocketCardKey(productId: productId, cardId: PocketCardId(value: cardId)),
            faceJson: faceJson
        )
    }

    func populate(entity: CDPocketCardFace, from model: StoredPocketCardFace, using _: NSManagedObjectContext) throws {
        entity.identifier = model.identifier
        entity.productId = model.key.productId
        entity.cardId = model.key.cardId.value
        entity.faceJson = model.faceJson
    }
}
