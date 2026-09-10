import Foundation
import SubstrateSdk

public extension ProofOfInkPallet {
    static var designFamiliesPath: StorageCodingPath {
        .init(moduleName: name, itemName: "DesignFamilies")
    }

    static var configPath: StorageCodingPath {
        .init(moduleName: name, itemName: "Configuration")
    }

    static var allocationCountPath: StorageCodingPath {
        .init(moduleName: name, itemName: "AllocationCount")
    }

    static var candidatesPath: StorageCodingPath {
        .init(moduleName: name, itemName: "Candidates")
    }

    static var committedDesignsPath: StorageCodingPath {
        .init(moduleName: name, itemName: "CommittedDesigns")
    }

    static var referralTicketsPath: StorageCodingPath {
        .init(moduleName: name, itemName: "ReferralTickets")
    }

    static var peoplePath: StorageCodingPath {
        .init(moduleName: name, itemName: "People")
    }

    static var pendingInvites: StorageCodingPath {
        .init(moduleName: name, itemName: "PendingInvites")
    }
}
