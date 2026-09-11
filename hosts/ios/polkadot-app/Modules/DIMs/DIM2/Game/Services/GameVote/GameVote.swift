import Foundation
import Operation_iOS
import CoreData
import SubstrateSdk
import Individuality

struct GameVote: Identifiable, Equatable {
    let gameIndex: GamePallet.GameIndex
    let accountId: AccountId
    let voteCounter: Int
    let isBanned: Bool
    let previewImageData: Data?
    let voteUpdateDate: Date?

    var identifier: String {
        Self.makeIdentifier(
            gameIndex: gameIndex,
            player: accountId
        )
    }

    var isPerson: Bool {
        voteCounter > 0
    }

    static func makeIdentifier(
        gameIndex: GamePallet.GameIndex,
        player: AccountId
    ) -> String {
        "\(gameIndex)-\(player.toHex())"
    }

    static func == (lhs: GameVote, rhs: GameVote) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

final class GameVoteMapper: CoreDataMapperProtocol {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = GameVote
    typealias CoreDataEntity = CDGameVote

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        entity.gameIndex = Int32(model.gameIndex)
        entity.accountId = model.accountId.toHex()
        entity.voteCounter = Int32(model.voteCounter)
        entity.isBanned = model.isBanned
        entity.previewImageData = model.previewImageData
        entity.voteUpdateDate = model.voteUpdateDate
        entity.identifier = model.identifier
    }

    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        guard let accountId = entity.accountId else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CoreDataEntity.accountId)
            )
        }

        return try GameVote(
            gameIndex: GamePallet.GameIndex(entity.gameIndex),
            accountId: accountId.fromHex(),
            voteCounter: Int(entity.voteCounter),
            isBanned: entity.isBanned,
            previewImageData: entity.previewImageData,
            voteUpdateDate: entity.voteUpdateDate
        )
    }
}
