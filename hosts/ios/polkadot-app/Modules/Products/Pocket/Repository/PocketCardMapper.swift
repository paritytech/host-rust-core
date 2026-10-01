import CoreData
import Operation_iOS
import Products

/// A card's membership row. Only cards the user added are stored; a host-placed
/// card is placed on every run and never persisted.
struct StoredPocketCard: Identifiable, Equatable {
    let key: PocketCardKey
    let title: String
    let addedAt: Date

    var identifier: String { key.storageId }
    var id: String { identifier }
}

final class PocketCardMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = StoredPocketCard
    typealias CoreDataEntity = CDPocketCard
}

extension PocketCardMapper: CoreDataMapperProtocol {
    func transform(entity: CDPocketCard) throws -> StoredPocketCard {
        guard let productId = entity.productId else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDPocketCard.productId))
        }

        guard let cardId = entity.cardId else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDPocketCard.cardId))
        }

        guard let title = entity.title else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDPocketCard.title))
        }

        return StoredPocketCard(
            key: PocketCardKey(productId: productId, cardId: PocketCardId(value: cardId)),
            title: title,
            addedAt: entity.addedAt ?? Date()
        )
    }

    func populate(entity: CDPocketCard, from model: StoredPocketCard, using _: NSManagedObjectContext) throws {
        entity.identifier = model.identifier
        entity.productId = model.key.productId
        entity.cardId = model.key.cardId.value
        entity.title = model.title
        entity.addedAt = model.addedAt
    }
}
