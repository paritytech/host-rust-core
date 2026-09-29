import Foundation

@Observable
public final class UpgradeUsernameViewModel: Hashable {
    public let liteUsername: String
    public let suggestedFullUsername: String
    public let mode: Mode

    public init(
        liteUsername: String,
        suggestedFullUsername: String,
        mode: Mode
    ) {
        self.liteUsername = liteUsername
        self.suggestedFullUsername = suggestedFullUsername
        self.mode = mode
    }

    public static func == (lhs: UpgradeUsernameViewModel, rhs: UpgradeUsernameViewModel) -> Bool {
        lhs.liteUsername == rhs.liteUsername &&
            lhs.suggestedFullUsername == rhs.suggestedFullUsername &&
            lhs.mode.stringValue == rhs.mode.stringValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(liteUsername)
        hasher.combine(suggestedFullUsername)
        hasher.combine(mode.stringValue)
    }
}

public extension UpgradeUsernameViewModel {
    enum Mode {
        case upgradeWidget(onUpgradeTap: () -> Void)
        case upgradedMessage

        var stringValue: String {
            switch self {
            case .upgradeWidget: "upgradeWidget"
            case .upgradedMessage: "upgradedMessage"
            }
        }
    }
}
