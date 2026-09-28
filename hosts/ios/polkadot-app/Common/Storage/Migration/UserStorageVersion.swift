import Foundation

enum UserStorageVersion: String, CaseIterable {
    case version41 = "UserDataModel41"
    case version42 = "UserDataModel42"
    case version43 = "UserDataModel43"
    case version44 = "UserDataModel44"
    case version45 = "UserDataModel45"
    case version46 = "UserDataModel46"
    case version47 = "UserDataModel47"
    case version48 = "UserDataModel48"
    case version49 = "UserDataModel49"
    case version50 = "UserDataModel50"
    case version51 = "UserDataModel51"
    case version52 = "UserDataModel52"
    /// Numbered well clear of the sequence `polkadot-ios-community` is still
    /// filling. The tree under `hosts/ios` is a snapshot of that repository and
    /// changes only ever move inwards, so a version authored here and one
    /// authored there would otherwise take the same name: the refresh would
    /// conflict on the file, and a device already migrated to this one would
    /// hold a store no bundled model matches, which ends in the migrator's
    /// `fatalError`.
    ///
    /// The hop below is re-pointed at this version each time a refresh brings a
    /// new upstream one, which is a conflict a human resolves rather than a
    /// crash a user meets.
    case version90 = "UserDataModel90"

    // swiftlint:disable:next cyclomatic_complexity
    func nextVersion() -> UserStorageVersion? {
        switch self {
        case .version41:
            .version42
        case .version42:
            .version43
        case .version43:
            .version44
        case .version44:
            .version45
        case .version45:
            .version46
        case .version46:
            .version47
        case .version47:
            .version48
        case .version48:
            .version49
        case .version49:
            .version50
        case .version50:
            .version51
        case .version51:
            .version52
        case .version52:
            .version90
        case .version90:
            nil
        }
    }
}
