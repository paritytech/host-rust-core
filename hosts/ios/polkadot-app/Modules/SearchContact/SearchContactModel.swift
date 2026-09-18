import Foundation

enum SearchContactSearchResult {
    case sections(AccountSearchSections<ContactSearchPayload, ContactSearchPayload>)
    case error(Error)
}

typealias SearchContactSearchState = SearchRunner.State<SearchContactSearchResult>

struct SearchContactModel {
    let didFoundChat: (ChatOpenModel) -> Void
}
