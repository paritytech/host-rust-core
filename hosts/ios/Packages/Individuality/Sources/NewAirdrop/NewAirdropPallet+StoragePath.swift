import SubstrateSdk
import SubstrateSdkExt

public extension NewAirdropPallet {
    static var events: StorageCodingPath {
        .init(moduleName: name, itemName: "Events")
    }

    static var actionSchedule: StorageCodingPath {
        .init(moduleName: name, itemName: "ActionSchedule")
    }

    static var registrations: StorageCodingPath {
        .init(moduleName: name, itemName: "Registrations")
    }

    static var winners: StorageCodingPath {
        .init(moduleName: name, itemName: "Winners")
    }

    static var eventEntropy: StorageCodingPath {
        .init(moduleName: name, itemName: "EventEntropy")
    }

    static var supportedAssets: StorageCodingPath {
        .init(moduleName: name, itemName: "SupportedAssets")
    }
}
