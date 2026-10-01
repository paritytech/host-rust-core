import CoreData
import Operation_iOS
import Products

/// The newest face held for a card, in the encoding the tree already travels
/// in, so the host keeps exactly what the protocol defines and nothing of its
/// own invention.
/// Kept apart from membership so a host-placed card, which has no membership
/// row, still keeps the face its product last drew.
struct StoredPocketCardFace: Identifiable, Equatable {
    let key: PocketCardKey
    let face: Data

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

        guard let face = entity.face else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDPocketCardFace.face))
        }

        return StoredPocketCardFace(
            key: PocketCardKey(productId: productId, cardId: PocketCardId(value: cardId)),
            face: face
        )
    }

    func populate(entity: CDPocketCardFace, from model: StoredPocketCardFace, using _: NSManagedObjectContext) throws {
        entity.identifier = model.identifier
        entity.productId = model.key.productId
        entity.cardId = model.key.cardId.value
        entity.face = model.face
    }
}
