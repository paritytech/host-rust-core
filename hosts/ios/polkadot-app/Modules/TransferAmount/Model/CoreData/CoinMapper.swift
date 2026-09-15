import Foundation
import CoreData
import Coinage
import Operation_iOS
import SubstrateSdk

/// Maps a `CDCoin` to the raw ``Coin`` — every stored field, no derived status. The durability
/// overlay is added separately by ``TrackedCoinMapper``.
final class CoinMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = Coin
    typealias CoreDataEntity = CDCoin
}

extension CoinMapper: CoreDataMapperProtocol {
    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        guard let handoffMark = CoinHandoffMark(rawValue: entity.handoffMark) else {
            throw CoreDataMapperError.unexpected(#keyPath(CDCoin.handoffMark))
        }

        guard let publicKeyHex = entity.publicKey else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoin.publicKey))
        }

        return try Coin(
            exponent: entity.exponent,
            derivationIndex: DerivationIndex.fromCoreData(entity.derivationIndex),
            age: entity.age?.int16Value,
            isOnchain: entity.isOnchain,
            handoffMark: handoffMark,
            publicKey: Data(hexString: publicKeyHex)
        )
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.derivationIndex = model.derivationIndex.toCoreData()
        entity.exponent = model.exponent
        entity.age = model.age.map { NSNumber(value: $0) }
        entity.isOnchain = model.isOnchain
        entity.handoffMark = model.handoffMark.rawValue
        entity.publicKey = model.publicKey.toHex()
    }
}
