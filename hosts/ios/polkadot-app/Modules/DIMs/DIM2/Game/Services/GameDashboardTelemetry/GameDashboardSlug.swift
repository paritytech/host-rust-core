import Foundation
import SubstrateSdk
import ChainRegistry
import SubstrateSdkExt

enum GameDashboardSlug {
    /// `account:<ss58>` per AOP slug format. Used for `who` and peer ids.
    /// Falls back to a hex-encoded variant if SS58 encoding fails — losing the prefix
    /// is preferable to dropping the telemetry entirely.
    static func account(_ accountId: AccountId, chainFormat: ChainFormat) -> String {
        "account:\(address(accountId, chainFormat: chainFormat))"
    }

    /// Bare SS58 (no AOP prefix). Used for `usernameAccountId` per the spec example.
    static func address(_ accountId: AccountId, chainFormat: ChainFormat) -> String {
        if let address = try? accountId.toAddress(using: chainFormat) {
            return address
        }
        return accountId.toHex(includePrefix: true)
    }
}
