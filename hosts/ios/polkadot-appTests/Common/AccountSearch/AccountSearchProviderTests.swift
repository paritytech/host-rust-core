import Testing
import SubstrateSdk
import Foundation
import AsyncExtensions
import Operation_iOS
import SDKLogger
import NovaCrypto
@testable import polkadot_app

struct AccountSearchProviderTests {
    // MARK: - Routing: empty/nil query

    @Test("Empty query uses allContacts() and skips global search")
    func emptyQueryUsesAllContacts() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: "")

        #expect(localSearch.didRequestAllContacts)
        #expect(localSearch.receivedUsernamePrefix == nil)
        #expect(localSearch.receivedAccountId == nil)
        #expect(remoteSearch.receivedSearchQuery == nil)
        #expect(remoteSearch.receivedFetchAccountId == nil)
    }

    @Test("Nil query uses allContacts() and skips global search")
    func nilQueryUsesAllContacts() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: nil)

        #expect(localSearch.didRequestAllContacts)
        #expect(localSearch.receivedUsernamePrefix == nil)
        #expect(localSearch.receivedAccountId == nil)
        #expect(remoteSearch.receivedSearchQuery == nil)
    }

    // MARK: - Routing: non-address query

    @Test("Non-address query uses searchContacts() and global search()")
    func nonAddressQueryUsesSearchContacts() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: "alice")

        #expect(localSearch.receivedUsernamePrefix == "alice")
        #expect(localSearch.receivedAccountId == nil)
        #expect(!localSearch.didRequestAllContacts)
        #expect(remoteSearch.receivedSearchQuery == "alice")
    }

    // MARK: - Routing: valid SS58 address

    @Test("Valid SS58 address uses contact() and fetch(), not searchContacts()")
    func validAddressUsesContactAndFetch() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)
        let targetAccountId = try Data.randomOrError(of: 32)
        let address = try SS58AddressFactory().address(fromAccountId: targetAccountId, type: 0)

        // Set fetchResult so fetch(by:) succeeds and search() is not called as fallback
        remoteSearch.fetchResult = try makeRemoteContact(accountId: targetAccountId, username: "found")

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: address)

        #expect(localSearch.receivedAccountId == targetAccountId)
        #expect(localSearch.receivedUsernamePrefix == nil)
        #expect(!localSearch.didRequestAllContacts)
        #expect(remoteSearch.receivedFetchAccountId == targetAccountId)
        #expect(remoteSearch.receivedSearchQuery == nil)
    }

    // MARK: - String normalization: trimmingDot

    @Test("Query with .dot suffix is trimmed before lookup")
    func trimmingDotRemovesSuffix() async throws {
        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        _ = try await provider.search(query: "alice.dot")

        #expect(localSearch.receivedUsernamePrefix == "alice")
        #expect(remoteSearch.receivedSearchQuery == "alice")
    }

    // MARK: - Filtering: blocked contacts

    @Test("Blocked contacts are filtered from results")
    func blockedContactsFiltered() async throws {
        let blockedContact = try makeContact(
            accountId: Data.randomOrError(of: 32),
            username: "blocked_user",
            isBlocked: true
        )
        let allowedContact = try makeContact(
            accountId: Data.randomOrError(of: 32),
            username: "allowed_user",
            isBlocked: false
        )

        let localSearch = MockLocalContactSearch()
        localSearch.contacts = [blockedContact, allowedContact]

        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        let result = try await provider.search(query: nil)

        #expect(result.contacts.count == 1)
        #expect(result.contacts[0].username?.value == "allowed_user")
    }

    // MARK: - Filtering: own account id

    @Test("Own account id is excluded from results")
    func ownAccountIdExcluded() async throws {
        let ownAccountId = try Data.randomOrError(of: 32)
        let otherAccountId = try Data.randomOrError(of: 32)

        let ownContact = makeContact(accountId: ownAccountId, username: "own")
        let otherContact = makeContact(accountId: otherAccountId, username: "other")

        let localSearch = MockLocalContactSearch()
        localSearch.contacts = [ownContact, otherContact]

        let remoteSearch = MockRemoteContactOperationFactory()

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        let result = try await provider.search(query: nil)

        #expect(result.contacts.count == 1)
        #expect(result.contacts[0].username?.value == "other")
    }

    // MARK: - Failure handling: global search failure

    @Test("Global search failure is tolerated, returns contacts without global section")
    func globalSearchFailureNotPropagated() async throws {
        let localSearch = MockLocalContactSearch()
        let contact = try makeContact(accountId: Data.randomOrError(of: 32), username: "local_user")
        localSearch.contacts = [contact]

        let remoteSearch = MockRemoteContactOperationFactory()
        remoteSearch.searchError = NSError(domain: "test", code: 1)

        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        let result = try await provider.search(query: "search")

        #expect(result.contacts.count == 1)
        #expect(result.global.isEmpty)
    }

    // MARK: - Recents stream updates

    @Test("Recents stream updates trigger sourcesChanged and appear in results")
    func recentsStreamUpdatesAppear() async throws {
        let (recentsStream, continuation) = AsyncStream<[SearchRow<Int>]>.makeStream()

        let recentId = try Data.randomOrError(of: 32)
        let recentRow = SearchRow(
            accountId: recentId,
            username: Username(value: "recent_user"),
            matchTerms: ["recent_user"],
            payload: 0
        )

        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { recentsStream.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        var sourcesChangedIterator = provider.sourcesChanged().makeAsyncIterator()
        provider.setup()

        continuation.yield([])
        _ = try await sourcesChangedIterator.next()

        continuation.yield([recentRow])
        _ = try await sourcesChangedIterator.next()

        let result = try await provider.search(query: nil)

        #expect(result.recent.count == 1)
        #expect(result.recent[0].username?.value == "recent_user")

        continuation.finish()
    }

    // MARK: - Remote contact fetch by id

    @Test("Remote contact fetch by valid address returns in global section")
    func remoteContactFetchByAddressReturns() async throws {
        let targetAccountId = try Data.randomOrError(of: 32)
        let address = try SS58AddressFactory().address(fromAccountId: targetAccountId, type: 0)

        let remoteContact = try makeRemoteContact(
            accountId: targetAccountId,
            username: "remote_user"
        )

        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        remoteSearch.fetchResult = remoteContact

        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        let result = try await provider.search(query: address)

        #expect(result.global.count == 1)
        #expect(result.global[0].username?.value == "remote_user")
    }

    // MARK: - Global search returns results

    @Test("Global search with non-address query returns results in global section")
    func globalSearchReturnsResults() async throws {
        let remoteContact = try makeRemoteContact(
            accountId: Data.randomOrError(of: 32),
            username: "search_result"
        )

        let localSearch = MockLocalContactSearch()
        let remoteSearch = MockRemoteContactOperationFactory()
        remoteSearch.searchResult = [remoteContact]

        let ownAccountId = try Data.randomOrError(of: 32)

        let provider: AccountSearchProvider<Int> = AccountSearchProvider(
            recentRowsStream: { AsyncStream<[SearchRow<Int>]> { _ in }.eraseToAnyAsyncSequence() },
            localContactSearch: localSearch,
            remoteContactSearch: remoteSearch,
            ownAccountId: ownAccountId,
            logger: MockLogger()
        )
        provider.setup()

        let result = try await provider.search(query: "search")

        #expect(result.global.count == 1)
        #expect(result.global[0].username?.value == "search_result")
    }
}

// MARK: - Helpers

private func makeContact(
    accountId: AccountId = Data(),
    username: String = "test_user",
    isBlocked: Bool = false
) -> Chat.Contact {
    Chat.Contact(
        accountId: accountId,
        username: username,
        publicKey: Data(repeating: 0, count: 32),
        pin: nil,
        pushId: nil,
        pushToken: nil,
        voipPushToken: nil,
        peerPlatform: nil,
        lastOwnToken: nil,
        voipLastOwnToken: nil,
        chatRequest: nil,
        ownKeyId: Chat.Contact.Own(signKeyId: "", encryptionKeyId: ""),
        imageData: nil,
        source: .chat,
        isBlocked: isBlocked,
        devices: [],
        pendingDevicesFanOut: false,
        addedAt: nil,
        acceptedAt: nil
    )
}

private func makeRemoteContact(
    accountId: AccountId = Data(),
    username: String = "test_remote"
) throws -> Chat.RemoteContact {
    try Chat.RemoteContact(
        accountId: accountId,
        username: username,
        chatPublicKey: Chat.PublicKey(rawData: Data(repeating: 0, count: 32)),
        imageData: nil,
        source: .chat
    )
}
