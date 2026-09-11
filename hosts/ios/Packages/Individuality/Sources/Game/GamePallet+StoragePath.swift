import SubstrateSdk
import SubstrateSdkExt

public extension GamePallet {
    static var game: StorageCodingPath {
        .init(moduleName: name, itemName: "Game")
    }

    static var players: StorageCodingPath {
        .init(moduleName: name, itemName: "Players")
    }

    static var indexToPlayer: StorageCodingPath {
        .init(moduleName: name, itemName: "IndexToPlayer")
    }

    static var playerToIndex: StorageCodingPath {
        .init(moduleName: name, itemName: "PlayerToIndex")
    }

    static var gameIndex: StorageCodingPath {
        .init(moduleName: name, itemName: "GameIndex")
    }

    static var gameSchedules: StorageCodingPath {
        .init(moduleName: name, itemName: "GameSchedules")
    }

    static var defaultPhaseDurations: ConstantCodingPath {
        .init(moduleName: name, constantName: "DefaultPhaseDurations")
    }

    static var pendingInvites: StorageCodingPath {
        .init(moduleName: name, itemName: "PendingInvites")
    }

    static var aliasToAccount: StorageCodingPath {
        .init(moduleName: name, itemName: "AliasToStmtAccount")
    }

    static var testnetPhaseDurations: StorageCodingPath {
        .init(moduleName: name, itemName: "StoredPhaseDurations")
    }

    static var gameHistory: StorageCodingPath {
        .init(moduleName: name, itemName: "GameHistory")
    }

    static var playerAttendanceHistory: StorageCodingPath {
        .init(moduleName: name, itemName: "PlayerAttendanceHistory")
    }

    static var archivedPlayers: StorageCodingPath {
        .init(moduleName: name, itemName: "ArchivedPlayers")
    }

    static var nfts: StorageCodingPath {
        .init(moduleName: name, itemName: "Nfts")
    }

    static var nftCandidates: StorageCodingPath {
        .init(moduleName: name, itemName: "NftCandidates")
    }
}

public extension GamePallet {
    enum Storage {
        case communicationIdentifier(AccountId)
    }
}

extension GamePallet.Storage: StoragePathConvertible {
    public var moduleName: String {
        GamePallet.name
    }

    public var name: String {
        switch self {
        case .communicationIdentifier:
            "CommunicationIdentifiers"
        }
    }
}
