import SubstrateSdk
import Foundation

struct AccountSearchSections<RecentPayload, MatchPayload> {
    let recent: [SearchRow<RecentPayload>]
    let contacts: [SearchRow<MatchPayload>]
    let global: [SearchRow<MatchPayload>]
}

enum AccountSearchComposer {
    static func compose<RecentPayload, MatchPayload>(
        query: String?,
        recent: [SearchRow<RecentPayload>],
        contacts: [SearchRow<MatchPayload>],
        global: [SearchRow<MatchPayload>],
        excluding: Set<AccountId>,
        maxRecent: Int = 5
    ) -> AccountSearchSections<RecentPayload, MatchPayload> {
        let filteredRecents = recent.filter { !excluding.contains($0.accountId) }

        let recentSection: [SearchRow<RecentPayload>]
        if let query, !query.isEmpty {
            let lowercasedQuery = query.lowercased()
            let matched = filteredRecents.filter { row in
                row.matchTerms.contains { term in
                    term.lowercased().hasPrefix(lowercasedQuery)
                }
            }
            recentSection = Array(matched.prefix(maxRecent))
        } else {
            recentSection = Array(filteredRecents.prefix(maxRecent))
        }

        let recentIds = Set(recentSection.map(\.accountId))

        let filteredContacts = contacts.filter { !excluding.contains($0.accountId) }
        let dedupedContacts = filteredContacts.filter { !recentIds.contains($0.accountId) }
        let contactsSection = dedupedContacts.sorted { lhs, rhs in
            sortByUsername(lhs.username, rhs.username)
        }

        let globalSection: [SearchRow<MatchPayload>]
        if let query, !query.isEmpty {
            let filteredGlobal = global.filter { !excluding.contains($0.accountId) }
            let allRecentAndContactIds = recentIds.union(dedupedContacts.map(\.accountId))
            let dedupedGlobal = filteredGlobal.filter { !allRecentAndContactIds.contains($0.accountId) }
            globalSection = dedupedGlobal.sorted { lhs, rhs in
                sortByUsername(lhs.username, rhs.username)
            }
        } else {
            globalSection = []
        }

        return AccountSearchSections(
            recent: recentSection,
            contacts: contactsSection,
            global: globalSection
        )
    }

    private static func sortByUsername(_ lhs: Username?, _ rhs: Username?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            false
        case (.none, _):
            false
        case (_, .none):
            true
        case let (lhsUsername?, rhsUsername?):
            lhsUsername < rhsUsername
        }
    }
}
