import Foundation
import PolkadotUI
import UIKit
import DesignSystem
import SubstrateSdk

@MainActor
final class SearchContactPresenter {
    weak var view: SearchContactViewProtocol?
    let wireframe: SearchContactWireframeProtocol
    let interactor: SearchContactInteractorInputProtocol

    private var currentSearch = CurrentSearch(
        query: "",
        state: .result(.contacts([]))
    )

    init(
        interactor: SearchContactInteractorInputProtocol,
        wireframe: SearchContactWireframeProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension SearchContactPresenter: SearchContactPresenterProtocol {
    func setup() {
        provideViewModel()
    }

    func search(username: String) {
        interactor.search(username: username)
    }

    func scanQRCode() {
        wireframe.showQRScan(from: view)
    }

    func didSelectContact(identifier: String) {
        guard let contact = currentSearch.contacts.first(where: { $0.username == identifier }) else {
            return
        }
        interactor.decide(on: contact)
    }
}

extension SearchContactPresenter: SearchContactInteractorOutputProtocol {
    func didReceive(searchState state: SearchContactSearchState, for query: String) {
        guard canApplySearchState(state, for: query) else {
            return
        }
        applySearchState(state, for: query)
    }

    func didReceive(error: any Error) {
        _ = wireframe.present(error: error, from: view)
    }

    func didReceive(resolution: ChatOpenModel) {
        wireframe.complete(from: view, with: resolution)
    }
}

private extension SearchContactPresenter {
    func canApplySearchState(_ state: SearchContactSearchState, for query: String) -> Bool {
        if case .started = state {
            return true
        }
        return query.isEmpty || currentSearch.query == query
    }

    func applySearchState(_ state: SearchContactSearchState, for query: String) {
        currentSearch = CurrentSearch(query: query, state: state)
        provideViewModel()
    }

    func provideViewModel() {
        let query = currentSearch.query
        let contacts = currentSearch.contacts
        let showHint = !currentSearch.isSearching && !currentSearch.queryFailed && contacts.isEmpty && query.isEmpty

        // TODO: Add Highlight for username + move to factory OR move logic into ui level
        let searchFailReason: NSAttributedString?
        if !currentSearch.isSearching, currentSearch.queryFailed || (!query.isEmpty && contacts.isEmpty) {
            let searchFailedString = String(localized: .searchContactNoSuchUsername(username: query))
            var attributes = LabelStyle.title16SemiBold().attributes(for: .center)
            attributes[.foregroundColor] = UIColor.fgSecondary
            searchFailReason = NSAttributedString(
                string: searchFailedString,
                attributes: attributes
            )
        } else {
            searchFailReason = nil
        }

        let viewModel = SearchContactViewLayout.ViewModel(
            contactsById: contacts.map { contact in
                let prefix = String(contact.username.prefix(1))
                let avatarViewModel = AvatarViewModel.colored(
                    text: prefix,
                    colorSeed: contact.accountId.toHex()
                )
                return SearchContactListConfiguration(
                    userName: contact.username,
                    avatarViewModel: avatarViewModel
                )
            }
            .identified { $0.userName },
            showHint: showHint,
            searchFailReason: searchFailReason,
            showsLoader: currentSearch.showsLoader,
            loaderText: currentSearch.loaderText
        )
        view?.didReceive(viewModel: viewModel)
    }

    struct CurrentSearch {
        let query: String
        let state: SearchContactSearchState

        var contacts: [Chat.RemoteContact] {
            guard case let .result(.contacts(contacts)) = state else {
                return []
            }
            return contacts.sorted { Username(value: $0.username) < Username(value: $1.username) }
        }

        var queryFailed: Bool {
            guard case .result(.error) = state else {
                return false
            }
            return true
        }

        var isSearching: Bool {
            switch state {
            case .started,
                 .waiting,
                 .waitingLong:
                true
            case .result:
                false
            }
        }

        var showsLoader: Bool {
            switch state {
            case .waiting,
                 .waitingLong:
                true
            case .started,
                 .result:
                false
            }
        }

        var loaderText: String? {
            guard case .waitingLong = state else {
                return nil
            }
            return String(localized: .searchContactLoadingLong)
        }
    }
}
