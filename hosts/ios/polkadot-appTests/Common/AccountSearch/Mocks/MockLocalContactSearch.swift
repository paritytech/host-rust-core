@testable import polkadot_app
import Foundation
import Operation_iOS
import SubstrateSdk

final class MockLocalContactSearch: LocalContactSearching {
    var contacts: [Chat.Contact] = []

    // Recorded inputs
    var receivedUsernamePrefix: String?
    var receivedAccountId: AccountId?
    var didRequestAllContacts: Bool = false
    var didRequestBlockedContacts: Bool = false

    func searchContacts(usernamePrefix: String) -> AnyDataProviderRepository<Chat.Contact> {
        receivedUsernamePrefix = usernamePrefix
        return makeSeededRepository()
    }

    func contact(accountId: AccountId) -> AnyDataProviderRepository<Chat.Contact> {
        receivedAccountId = accountId
        return makeSeededRepository()
    }

    func allContacts() -> AnyDataProviderRepository<Chat.Contact> {
        didRequestAllContacts = true
        return makeSeededRepository()
    }

    func blockedContacts() -> AnyDataProviderRepository<Chat.Contact> {
        didRequestBlockedContacts = true
        return makeRepository(with: contacts.filter(\.isBlocked))
    }

    private func makeRepository(with contacts: [Chat.Contact]) -> AnyDataProviderRepository<Chat.Contact> {
        let repository = InMemoryDataProviderRepository<Chat.Contact>()
        // `start()` runs the operation inline; an OperationQueue wait here would block
        // a cooperative-pool thread, since callers seed from an async context.
        repository.replaceOperation { contacts }.start()
        return AnyDataProviderRepository(repository)
    }

    private func makeSeededRepository() -> AnyDataProviderRepository<Chat.Contact> {
        makeRepository(with: contacts)
    }
}
