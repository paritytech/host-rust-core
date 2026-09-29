import SubstrateSdk

public extension ScorePallet {
    static var participants: StorageCodingPath {
        .init(moduleName: name, itemName: "Participants")
    }

    static var personhoodThreshold: StorageCodingPath {
        .init(moduleName: name, itemName: "PersonhoodThreshold")
    }

    static var voucherType: ConstantCodingPath {
        .init(moduleName: name, constantName: "VoucherType")
    }
}
