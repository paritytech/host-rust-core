import Foundation
import SubstrateSdkExt

struct RecipientViewModel: Hashable {
    let accountType: SearchAccountViewModel.AccountType
    let recentContactID: String
}

protocol RecipientViewModelFactoryProtocol {
    func createRecentContacts(from recentContactsMap: [String: RecentContactModelWithUsername]) -> [RecipientViewModel]
}

final class RecipientViewModelFactory: RecipientViewModelFactoryProtocol {
    func createRecentContacts(from recentContactsMap: [String: RecentContactModelWithUsername])
        -> [RecipientViewModel] {
        mapRecentContactsToRecentContactWithAccountType(recentContactsMap: recentContactsMap)
    }

    private func mapRecentContactsToRecentContactWithAccountType(
        recentContactsMap: [String: RecentContactModelWithUsername]
    ) -> [RecipientViewModel] {
        let items = recentContactsMap.values.sorted(by: { $0.recentContact.lastUsed > $1.recentContact.lastUsed })
        return items.compactMap { item in
            guard
                let chainFormat = item.chainAsset?.chain.chainFormat,
                let accountAddress = try? item.recentContact.accountID.toAddress(using: chainFormat)
            else {
                return nil
            }

            let accountType: SearchAccountViewModel.AccountType =
                if let username = item.username,
                !username.value.isEmpty {
                    .username(username.value, accountAddress)
                } else {
                    .accountAddress(accountAddress)
                }

            return RecipientViewModel(accountType: accountType, recentContactID: item.recentContact.identifier)
        }
    }
}
