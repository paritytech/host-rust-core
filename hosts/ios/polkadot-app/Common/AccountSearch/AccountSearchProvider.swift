import Foundation
import SubstrateSdk
import AsyncExtensions
import StructuredConcurrency
import os
import Operation_iOS
import SDKLogger

final class AccountSearchProvider<RecentPayload: Sendable>: AccountSearching {
    typealias MatchPayload = ContactSearchPayload

    private let recentRowsStream: @Sendable () -> AnyAsyncSequence<[SearchRow<RecentPayload>]>
    private let localContactSearch: LocalContactSearching
    private let remoteContactSearch: RemoteContactOperationMaking
    private let ownAccountId: AccountId
    private let logger: LoggerProtocol
    private let stateLock: OSAllocatedUnfairLock<State>
    private let sourcesChangedNotifier = SourcesChangedNotifier()

    init(
        recentRowsStream: @escaping @Sendable () -> AnyAsyncSequence<[SearchRow<RecentPayload>]>,
        localContactSearch: LocalContactSearching,
        remoteContactSearch: RemoteContactOperationMaking,
        ownAccountId: AccountId,
        logger: LoggerProtocol
    ) {
        self.recentRowsStream = recentRowsStream
        self.localContactSearch = localContactSearch
        self.remoteContactSearch = remoteContactSearch
        self.ownAccountId = ownAccountId
        self.logger = logger
        stateLock = OSAllocatedUnfairLock(initialState: State())
    }

    deinit {
        replaceRecentSubscriptionTask(with: nil)
        sourcesChangedNotifier.finish()
    }

    func setup() {
        subscribeToRecent()
    }

    func sourcesChanged() -> AnyAsyncSequence<Void> {
        sourcesChangedNotifier.sequence()
    }

    func search(query: String?) async throws -> AccountSearchSections<RecentPayload, MatchPayload> {
        let recent = stateLock.withLock { $0.recentRows }

        async let blockedIds = fetchBlockedAccountIds()
        let matches = try await fetchMatches(for: query)

        let excluded = try await blockedIds.union([ownAccountId])
        return AccountSearchComposer.compose(
            query: query,
            recent: recent,
            contacts: matches.contacts,
            global: matches.global,
            excluding: excluded
        )
    }
}

private extension AccountSearchProvider {
    struct State {
        var recentRows: [SearchRow<RecentPayload>] = []
        var recentSubscriptionTask: Task<Void, Never>?
    }

    /// An empty query lists every stored contact and skips the global lookup entirely.
    func fetchMatches(
        for query: String?
    ) async throws -> (contacts: [SearchRow<MatchPayload>], global: [SearchRow<MatchPayload>]) {
        guard let query, !query.isEmpty else {
            let contacts = try await fetchLocalContacts(matching: nil, accountId: nil)
            return (contacts: contacts, global: [])
        }

        let normalizedQuery = query.trimmingDot()
        let accountId = try? normalizedQuery.toAccountId()

        async let localRows = fetchLocalContacts(matching: normalizedQuery, accountId: accountId)
        async let globalRows = fetchGlobalContacts(query: normalizedQuery, accountId: accountId)

        let contacts = try await localRows
        let global = try await globalRows

        return (contacts: contacts, global: global)
    }

    func subscribeToRecent() {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in recentRowsStream() {
                    guard !Task.isCancelled else { return }
                    stateLock.withLock { $0.recentRows = rows }
                    sourcesChangedNotifier.notify()
                }
            } catch {
                logger.error("Recent subscription error: \(error)")
            }
        }
        replaceRecentSubscriptionTask(with: task)
    }

    /// Swaps the stored handle under the lock and cancels the displaced task outside it,
    /// so a second `setup()` cannot orphan a running subscription.
    func replaceRecentSubscriptionTask(with task: Task<Void, Never>?) {
        let previous = stateLock.withLock { state in
            let previous = state.recentSubscriptionTask
            state.recentSubscriptionTask = task
            return previous
        }

        previous?.cancel()
    }

    /// Blocked contacts are excluded from every section, including remote results
    /// that the local lookup never returns.
    func fetchBlockedAccountIds() async throws -> Set<AccountId> {
        let repository = localContactSearch.blockedContacts()

        let contacts = try await repository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()

        return Set(contacts.map(\.accountId))
    }

    /// An account id takes precedence over a username prefix, since an exact address match
    /// is never also a username. A nil prefix with no account id fetches every stored contact.
    func fetchLocalContacts(
        matching usernamePrefix: String?,
        accountId: AccountId?
    ) async throws -> [SearchRow<MatchPayload>] {
        let repository =
            if let accountId {
                localContactSearch.contact(accountId: accountId)
            } else if let usernamePrefix {
                localContactSearch.searchContacts(usernamePrefix: usernamePrefix)
            } else {
                localContactSearch.allContacts()
            }

        let contacts = try await repository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()

        return contacts
            .map { contact in
                SearchRow(
                    accountId: contact.accountId,
                    username: Username(value: contact.username),
                    matchTerms: [contact.username],
                    payload: .local(contact)
                )
            }
    }

    func fetchGlobalContacts(query: String, accountId: AccountId?) async throws -> [SearchRow<MatchPayload>] {
        do {
            if let accountId {
                let account = try await remoteContactSearch.fetch(by: accountId)
                try Task.checkCancellation()

                return account.map { [makeRemoteRow(contact: $0)] } ?? []
            }

            let contacts = try await remoteContactSearch.search(by: query).asyncExecute()
            try Task.checkCancellation()

            return contacts.map { makeRemoteRow(contact: $0) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.warning("Global contact search failed, continuing without global results: \(error)")
            return []
        }
    }

    func makeRemoteRow(contact: Chat.RemoteContact) -> SearchRow<MatchPayload> {
        SearchRow(
            accountId: contact.accountId,
            username: Username(value: contact.username),
            matchTerms: [contact.username],
            payload: .remote(contact)
        )
    }
}
