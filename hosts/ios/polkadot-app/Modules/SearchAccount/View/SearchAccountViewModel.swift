import UIKit
import Foundation_iOS
import SubstrateSdk

struct SearchAccountViewModel {
    let inputViewModel: InputModel
    let dataType: DataType

    init(
        inputViewModel: InputModel = InputModel(
            inputViewModel: InputViewModel.createAccountInputViewModel(for: "")
        ),
        dataType: DataType = .idle(recent: [], contacts: [])
    ) {
        self.inputViewModel = inputViewModel
        self.dataType = dataType
    }
}

extension SearchAccountViewModel {
    enum Section: Hashable {
        case `default`
        case recentContacts
    }

    enum AccountType: Hashable {
        case username(String, AccountAddress)
        case accountAddress(AccountAddress)
    }

    struct InputModel {
        let inputViewModel: InputViewModelProtocol
        var selectedAccount: AccountType?
    }

    enum DataType {
        case idle(recent: [RecipientViewModel], contacts: [AccountType])
        case searchResults([AccountType])
    }
}

extension SearchAccountViewModel.AccountType {
    var title: String {
        switch self {
        case let .username(username, _): username
        case let .accountAddress(accountAddress): accountAddress
        }
    }

    var accountAddress: AccountAddress {
        switch self {
        case let .username(_, accountAddress),
             let .accountAddress(accountAddress):
            accountAddress
        }
    }
}

extension SearchAccountViewModel.Section {
    var title: String? {
        switch self {
        case .default: nil
        case .recentContacts: String(localized: .transactionSearchRecentContacts)
        }
    }
}
