import Foundation
import SubstrateSdkExt

public extension ResourcesPallet {
    enum Constants {
        case longTermStoragePeriodDuration
    }
}

extension ResourcesPallet.Constants: ConstantPathConvertible {
    public var name: String {
        switch self {
        case .longTermStoragePeriodDuration:
            "LongTermStoragePeriodDuration"
        }
    }

    public var moduleName: String { ResourcesPallet.name }
}
