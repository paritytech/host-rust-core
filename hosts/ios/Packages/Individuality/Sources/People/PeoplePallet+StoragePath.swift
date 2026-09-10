import Foundation
import SubstrateSdk

public extension PeoplePallet {
    static var memberKeysPath: StorageCodingPath {
        .init(moduleName: name, itemName: "Keys")
    }

    static var accountToAliasPath: StorageCodingPath {
        .init(moduleName: name, itemName: "AccountToAlias")
    }

    static var peoplePath: StorageCodingPath {
        .init(moduleName: name, itemName: "People")
    }

    static var nextPeopleIdPath: StorageCodingPath {
        .init(moduleName: name, itemName: "NextPersonalId")
    }
}
