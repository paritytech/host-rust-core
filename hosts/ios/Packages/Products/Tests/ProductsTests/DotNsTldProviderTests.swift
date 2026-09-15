import Foundation
import Testing
@testable import Products

// MARK: - Stubs

private final class StubTldReader: DotNsTldReading {
    var readTldCallCount = 0
    var readTldResult: Result<String, any Error> = .failure(DotNsContractError.tldNotFound)
    var yieldsBeforeReturning = false

    func readTld() async throws -> String {
        readTldCallCount += 1

        if yieldsBeforeReturning {
            await Task.yield()
        }

        return try readTldResult.get()
    }
}

private final class StubDotNsTldStore: DotNsTldStoring {
    var loadedTld: String?
    var savedTlds: [String] = []

    func loadTld() -> String? {
        loadedTld
    }

    func saveTld(_ tld: String) {
        savedTlds.append(tld)
    }
}

/// Test clock whose reading can be moved forward between assertions.
private final class MutableClock {
    var seconds: Double = 0
}

// MARK: - Tests

struct DotNsTldProviderTests {
    @Test func currentTldIsNilBeforeSuccessfulRead() {
        let stub = StubTldReader()
        stub.readTldResult = .success("dot")
        let provider = DotNsTldProvider(reader: stub)

        #expect(provider.currentTld() == nil)
    }

    @Test func currentTldReturnsValueAfterSuccessfulResolve() async throws {
        let stub = StubTldReader()
        stub.readTldResult = .success("dot")
        let provider = DotNsTldProvider(reader: stub)

        _ = try await provider.resolveTld()

        #expect(provider.currentTld() == "dot")
    }

    @Test func resolveTldDoesNotCallReadTldAgainAfterSuccess() async throws {
        let stub = StubTldReader()
        stub.readTldResult = .success("dot")
        let provider = DotNsTldProvider(reader: stub)

        _ = try await provider.resolveTld()
        _ = provider.currentTld()

        #expect(stub.readTldCallCount == 1)
    }

    @Test func multipleConcurrentResolveCallsResultInSingleRead() async throws {
        let stub = StubTldReader()
        stub.readTldResult = .success("dot")
        stub.yieldsBeforeReturning = true
        let provider = DotNsTldProvider(reader: stub)

        async let first = provider.resolveTld()
        async let second = provider.resolveTld()

        let firstTld = try await first
        let secondTld = try await second

        #expect(firstTld == "dot")
        #expect(secondTld == "dot")
        #expect(stub.readTldCallCount == 1)
    }

    @Test func failureLeavesCacheEmpty() async {
        let stub = StubTldReader()
        stub.readTldResult = .failure(DotNsContractError.contentHashNotFound)
        let provider = DotNsTldProvider(reader: stub)

        await #expect(throws: DotNsContractError.self) {
            _ = try await provider.resolveTld()
        }

        #expect(provider.currentTld() == nil)
    }

    @Test func retryAfterBackoffSucceeds() async throws {
        let stub = StubTldReader()
        stub.readTldResult = .failure(DotNsContractError.contentHashNotFound)
        let clock = MutableClock()
        let provider = DotNsTldProvider(
            reader: stub,
            now: { Date(timeIntervalSince1970: clock.seconds) }
        )

        await #expect(throws: DotNsContractError.self) {
            _ = try await provider.resolveTld()
        }

        clock.seconds = 4
        stub.readTldResult = .success("dot")

        let tld = try await provider.resolveTld()

        #expect(tld == "dot")
    }

    @Test func noReadWhileInBackoffWindow() async {
        let stub = StubTldReader()
        stub.readTldResult = .failure(DotNsContractError.contentHashNotFound)
        let clock = MutableClock()
        let provider = DotNsTldProvider(
            reader: stub,
            now: { Date(timeIntervalSince1970: clock.seconds) }
        )

        await #expect(throws: DotNsContractError.self) {
            _ = try await provider.resolveTld()
        }

        let callCountAfterFailure = stub.readTldCallCount

        clock.seconds = 0.5
        _ = provider.currentTld()

        #expect(stub.readTldCallCount == callCountAfterFailure)
    }

    @Test func currentTldReturnsPersistedValueImmediately() {
        let stub = StubTldReader()
        let store = StubDotNsTldStore()
        store.loadedTld = "dot"
        let provider = DotNsTldProvider(reader: stub, store: store)

        #expect(provider.currentTld() == "dot")
    }

    @Test func successfulResolvePersistsValue() async throws {
        let stub = StubTldReader()
        stub.readTldResult = .success("dot")
        let store = StubDotNsTldStore()
        let provider = DotNsTldProvider(reader: stub, store: store)

        _ = try await provider.resolveTld()

        #expect(store.savedTlds == ["dot"])
    }

    @Test func failedReadLeavesPersistedValueInCurrentTld() async {
        let stub = StubTldReader()
        stub.readTldResult = .failure(DotNsContractError.contentHashNotFound)
        let store = StubDotNsTldStore()
        store.loadedTld = "dot"
        let provider = DotNsTldProvider(reader: stub, store: store)

        await #expect(throws: DotNsContractError.self) {
            _ = try await provider.resolveTld()
        }

        #expect(provider.currentTld() == "dot")
    }

    @Test func noStoreNoSuccessfulReadReturnsNil() {
        let stub = StubTldReader()
        let provider = DotNsTldProvider(reader: stub, store: nil)

        #expect(provider.currentTld() == nil)
    }
}
