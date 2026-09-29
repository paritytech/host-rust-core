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
        state: .result(.sections(AccountSearchSections(recent: [], contacts: [], global: [])))
    )

    private var selection: [String: ContactSearchPayload] = [:]

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
        interactor.setup()
        provideViewModel(sections: AccountSearchSections(recent: [], contacts: [], global: []))
    }

    func search(username: String) {
        interactor.search(username: username)
    }

    func didSelectContact(identifier: String) {
        guard let contact = findContact(by: identifier) else {
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

        switch state {
        case let .result(.sections(sections)):
            selection = Dictionary(
                (sections.recent + sections.contacts + sections.global)
                    .map { ($0.payload.accountId.toHex(), $0.payload) },
                uniquingKeysWith: { first, _ in first }
            )
            provideViewModel(sections: sections)
        case .result(.error):
            selection = [:]
            provideViewModel(sections: AccountSearchSections(recent: [], contacts: [], global: []))
        case .started,
             .waiting,
             .waitingLong:
            provideStatus()
        }
    }

    func makeStatus() -> SearchContactResultsView.StatusViewModel {
        SearchContactResultsView.StatusViewModel(
            message: makeStatusMessage(),
            showsLoader: currentSearch.showsLoader,
            loaderText: currentSearch.loaderText
        )
    }

    /// Shown instead of the rows once the search settles: the failure reason, or the
    /// no-recents hint when the field is empty.
    func makeStatusMessage() -> NSAttributedString? {
        guard !currentSearch.isSearching else {
            return nil
        }

        let query = currentSearch.query
        let allEmpty = selection.isEmpty

        if currentSearch.queryFailed || (!query.isEmpty && allEmpty) {
            return makeCenteredMessage(String(localized: .searchContactNoSuchUsername(username: query)))
        } else if allEmpty, query.isEmpty {
            return makeCenteredMessage(String(localized: .searchContactNoRecentSearches))
        } else {
            return nil
        }
    }

    func makeCenteredMessage(_ text: String) -> NSAttributedString {
        var attributes = LabelStyle.title16SemiBold().attributes(for: .center)
        attributes[.foregroundColor] = UIColor.fgSecondary
        return NSAttributedString(string: text, attributes: attributes)
    }

    func provideStatus() {
        view?.didReceive(status: makeStatus())
    }

    func provideViewModel(sections: AccountSearchSections<ContactSearchPayload, ContactSearchPayload>) {
        let viewModel = SearchContactResultsView.ViewModel(
            sections: buildViewSections(from: sections),
            status: makeStatus()
        )

        view?.didReceive(viewModel: viewModel)
    }

    func buildViewSections(
        from sections: AccountSearchSections<ContactSearchPayload, ContactSearchPayload>
    ) -> [SearchContactResultsView.ViewModel.Section] {
        [
            makeViewSection(
                id: "recent",
                title: String(localized: .searchContactRecentChats),
                rows: sections.recent
            ),
            makeViewSection(
                id: "contacts",
                title: String(localized: .transactionSearchMyContacts),
                rows: sections.contacts
            ),
            makeViewSection(
                id: "global",
                title: String(localized: .transactionSearchAllUsers),
                rows: sections.global
            )
        ].compactMap { $0 }
    }

    func makeViewSection(
        id: String,
        title: String,
        rows: [SearchRow<ContactSearchPayload>]
    ) -> SearchContactResultsView.ViewModel.Section? {
        guard !rows.isEmpty else { return nil }

        return SearchContactResultsView.ViewModel.Section(
            id: id,
            title: title,
            rows: rows.map { row in
                IdentifiableContentConfiguration(
                    id: row.payload.accountId.toHex(),
                    configuration: makeListConfiguration(for: row.payload)
                )
            }
        )
    }

    func makeListConfiguration(for payload: ContactSearchPayload) -> SearchContactListConfiguration {
        let prefix = String(payload.username.prefix(1))
        let avatarViewModel = AvatarViewModel.colored(
            text: prefix,
            colorSeed: payload.accountId.toHex()
        )
        return SearchContactListConfiguration(
            userName: payload.username,
            avatarViewModel: avatarViewModel
        )
    }

    func findContact(by identifier: String) -> ContactSearchPayload? {
        selection[identifier]
    }

    struct CurrentSearch {
        let query: String
        let state: SearchContactSearchState

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
