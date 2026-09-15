import Foundation
import CoreData
import Coinage
import Operation_iOS

/// Maps a `CDCoin` to a ``TrackedCoin`` — the raw coin plus the durability overlay derived from its
/// input/output entry relations. Read-only: `populate` is unsupported.
final class TrackedCoinMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = TrackedCoin
    typealias CoreDataEntity = CDCoin

    private let coinMapper = CoinMapper()
}

extension TrackedCoinMapper: CoreDataMapperProtocol {
    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        let coin = try coinMapper.transform(entity: entity)
        return TrackedCoin(
            coin: coin,
            state: CoinageAssetStateDeriver.state(
                handedOff: coin.handoffMark != .none,
                inputs: entity.coinageTxInputs,
                output: entity.coinageTxOutput
            )
        )
    }

    func populate(
        entity _: CoreDataEntity,
        from _: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        throw CoreDataMapperError.unsupported
    }
}
