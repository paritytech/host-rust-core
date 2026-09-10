import Foundation
import SubstrateSdk

extension PrivacyVoucherPallet {
    static var keysToRing: StorageCodingPath {
        .init(moduleName: name, itemName: "KeysToRing")
    }

    static var rings: StorageCodingPath {
        .init(moduleName: name, itemName: "Rings")
    }

    static var buildingRings: StorageCodingPath {
        .init(moduleName: name, itemName: "BuildingRings")
    }

    static var keysPath: StorageCodingPath {
        .init(moduleName: name, itemName: "Keys")
    }

    static var usedTickets: StorageCodingPath {
        .init(moduleName: name, itemName: "UsedTickets")
    }
}
