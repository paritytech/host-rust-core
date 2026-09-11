import Testing
import Combine
import CommonService
import KeyDerivation
import SubstrateSdk
import StructuredConcurrency
import EventCenter
@testable import polkadot_app

@Suite("IdentityProfileService")
struct IdentityProfileServiceTests {
    private let storage: MockUsernameStorage
    private let identityService: MockIdentityService
    let personDataStore: MockObservableStore<DetermineStatePersonData>
    let wallet: WalletManaging
    let eventCenter: MockEventCenter

    init() throws {
        storage = MockUsernameStorage()
        identityService = MockIdentityService()
        personDataStore = MockObservableStore<DetermineStatePersonData>(logger: MockLogger())
        wallet = try MockWalletManager.mockedWallet()
        eventCenter = MockEventCenter()
    }

    func createSut() -> (IdentityProfileServiceProtocol & AppEventVisiting) {
        IdentityProfileService(
            usernameStorage: storage,
            identityService: identityService,
            personDataStore: personDataStore,
            wallet: wallet,
            eventCenter: eventCenter,
            logger: MockLogger()
        )
    }

    @Test("Init seeds profile from storage values")
    func initSeedsProfileFromStorage() async throws {
        storage.username = Username(value: "alice")
        storage.usernameClaimed = true
        storage.isPerson = true

        let sut = createSut()
        let profile = try await sut.observe()
            .first(where: { _ in true })

        let first = try #require(profile)

        #expect(first.username == Username(value: "alice"))
        #expect(first.isClaimed)
        #expect(first.rank == .membership)
    }

    @Test("Init emits empty profile when storage is empty")
    func initSeedsEmptyProfileWhenStorageEmpty() async throws {
        let sut = createSut()
        let profile = try await sut.observe()
            .first(where: { _ in true })

        let first = try #require(profile)

        #expect(first.username == nil)
        #expect(!first.isClaimed)
        #expect(first.rank == .basic)
    }

    @Test("On-chain subscription claims username and emits update")
    func onChainSubscriptionClaimsUsername() async throws {
        storage.username = Username(value: "alice.22")
        storage.usernameClaimed = false
        let sut = createSut()
        async let profiles = try withTimeout(.seconds(5)) {
            try await sut.observe()
                .prefix(2)
                .reduce([]) { $0 + [$1] }
        }

        try await Task.sleep(for: .seconds(1))
        identityService.subject.send(Username(value: "aliceclaimed"))

        let collected = try await profiles
        let claimed = try #require(collected.last)

        #expect(claimed.isClaimed)
        #expect(claimed.username == Username(value: "aliceclaimed"))
        #expect(storage.username == Username(value: "aliceclaimed"))
        #expect(storage.usernameClaimed)
    }

    @Test("On-chain subscription skipped when already claimed")
    func onChainSubscriptionSkippedWhenAlreadyClaimed() async throws {
        storage.username = Username(value: "alice")
        storage.usernameClaimed = true
        let sut = createSut()
        async let profile = try sut.observe()
            .first(where: { _ in true })

        _ = try await profile
        try await Task.sleep(for: .seconds(0.1))

        #expect(identityService.subscribeCallCount == 0)
    }

    @Test("On-chain subscription skipped when no username")
    func onChainSubscriptionSkippedWhenNoUsername() async throws {
        let sut = createSut()
        async let profile = try sut.observe()
            .first(where: { _ in true })

        _ = try await profile

        try await Task.sleep(for: .seconds(0.1))

        #expect(identityService.subscribeCallCount == 0)
    }

    @Test("SelectedUsernameChanged event emits refreshed profile")
    func processSelectedUsernameChangedEmitsRefreshedProfile() async throws {
        let sut = createSut()
        async let profiles = try withTimeout(.seconds(5)) {
            try await sut.observe()
                .prefix(2)
                .reduce([]) { $0 + [$1] }
        }

        try await Task.sleep(for: .seconds(0.1))
        storage.username = Username(value: "bob")
        sut.processSelectedUsernameChanged(event: SelectedUsernameChanged(username: storage.username))

        let collected = try await profiles
        #expect(collected.last?.username == Username(value: "bob"))
    }
}

private final class MockUsernameStorage: UsernameStoring, @unchecked Sendable {
    var username: Username?
    var usernameClaimed: Bool = false
    var isPerson: Bool = false
}

private final class MockIdentityService: IdentityServiceProtocol, @unchecked Sendable {
    let subject = CurrentValueSubject<Username?, Error>(nil)
    private(set) var subscribeCallCount = 0

    func subscribe(to _: AccountId) -> AnyPublisher<Username?, Error> {
        subscribeCallCount += 1
        return subject.eraseToAnyPublisher()
    }

    func username(for _: AccountId) -> AnyPublisher<Username?, Error> {
        Just<Username?>(nil).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
}
