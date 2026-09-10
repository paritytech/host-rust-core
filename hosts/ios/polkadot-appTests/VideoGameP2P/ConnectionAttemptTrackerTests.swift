@testable import polkadot_app
import Foundation
import SubstrateSdk
import Keystore_iOS
import Testing

@Suite(.serialized)
struct ConnectionAttemptTrackerTests {
    private func makeSUT() -> ConnectionAttemptTracker {
        ConnectionAttemptTracker(settingsManager: InMemorySettingsManager())
    }

    private func makeAccountId(_ byte: UInt8) -> AccountId {
        Data(repeating: byte, count: 32)
    }

    @Test("Returns nil when no offer ID persisted")
    func returnsNilWhenEmpty() {
        let sut = makeSUT()

        let result = sut.getLastOfferId(
            gameIndex: 1,
            remoteAccountId: makeAccountId(0x01)
        )

        #expect(result == nil)
    }

    @Test("Persists and retrieves offer ID")
    func persistsAndRetrieves() {
        let sut = makeSUT()
        let accountId = makeAccountId(0x02)

        sut.persistOfferId("offer-123", gameIndex: 5, remoteAccountId: accountId)

        let result = sut.getLastOfferId(gameIndex: 5, remoteAccountId: accountId)
        #expect(result == "offer-123")
    }

    @Test("Clears persisted offer ID")
    func clearsOfferId() {
        let sut = makeSUT()
        let accountId = makeAccountId(0x03)

        sut.persistOfferId("offer-456", gameIndex: 10, remoteAccountId: accountId)
        sut.clearOfferId(gameIndex: 10, remoteAccountId: accountId)

        let result = sut.getLastOfferId(gameIndex: 10, remoteAccountId: accountId)
        #expect(result == nil)
    }

    @Test("Overwrites existing offer ID")
    func overwritesExisting() {
        let sut = makeSUT()
        let accountId = makeAccountId(0x04)

        sut.persistOfferId("first", gameIndex: 1, remoteAccountId: accountId)
        sut.persistOfferId("second", gameIndex: 1, remoteAccountId: accountId)

        let result = sut.getLastOfferId(gameIndex: 1, remoteAccountId: accountId)
        #expect(result == "second")
    }

    @Test("Isolates offer IDs by game index")
    func isolatesByGameIndex() {
        let sut = makeSUT()
        let accountId = makeAccountId(0x05)

        sut.persistOfferId("game1-offer", gameIndex: 1, remoteAccountId: accountId)
        sut.persistOfferId("game2-offer", gameIndex: 2, remoteAccountId: accountId)

        #expect(sut.getLastOfferId(gameIndex: 1, remoteAccountId: accountId) == "game1-offer")
        #expect(sut.getLastOfferId(gameIndex: 2, remoteAccountId: accountId) == "game2-offer")
    }

    @Test("Isolates offer IDs by remote account ID")
    func isolatesByAccountId() {
        let sut = makeSUT()
        let account1 = makeAccountId(0x0A)
        let account2 = makeAccountId(0x0B)

        sut.persistOfferId("peer1-offer", gameIndex: 1, remoteAccountId: account1)
        sut.persistOfferId("peer2-offer", gameIndex: 1, remoteAccountId: account2)

        #expect(sut.getLastOfferId(gameIndex: 1, remoteAccountId: account1) == "peer1-offer")
        #expect(sut.getLastOfferId(gameIndex: 1, remoteAccountId: account2) == "peer2-offer")
    }

    @Test("Clear only affects targeted entry")
    func clearOnlyAffectsTarget() {
        let sut = makeSUT()
        let account1 = makeAccountId(0x10)
        let account2 = makeAccountId(0x20)

        sut.persistOfferId("offer-a", gameIndex: 1, remoteAccountId: account1)
        sut.persistOfferId("offer-b", gameIndex: 1, remoteAccountId: account2)

        sut.clearOfferId(gameIndex: 1, remoteAccountId: account1)

        #expect(sut.getLastOfferId(gameIndex: 1, remoteAccountId: account1) == nil)
        #expect(sut.getLastOfferId(gameIndex: 1, remoteAccountId: account2) == "offer-b")
    }
}
