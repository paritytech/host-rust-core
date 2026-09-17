import Foundation
import SubstrateSdk

struct SearchAccountResult {
    struct Contact {
        let username: String?
        let address: AccountAddress
    }

    let recent: [RecentContactModelWithUsername]
    let contacts: [Contact]
    let global: [Contact]
}
