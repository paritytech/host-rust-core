import Foundation

enum SearchContactSearchResult {
    case contacts([Chat.RemoteContact])
    case error(Error)
}

typealias SearchContactSearchState = SearchRunner.State<SearchContactSearchResult>

struct SearchContactModel {
    let didFoundChat: (ChatOpenModel) -> Void
}
